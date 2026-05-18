#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/package_loader.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/upstream_github_release.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/upstream_custom_hook.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/package_pipeline.sh"

STATE_FILE=${UPDATE_STATE_FILE:-.update-state/upstream-state.tsv}
PACKAGE_FILTER=""
CACHE_POLICY=normal
DISPATCH_POLICY=auto
PACKAGES=()
CHANGED_PACKAGES=()

declare -A PREVIOUS_FINGERPRINTS=()
declare -A PREVIOUS_LINES=()
declare -A PROCESSED_PACKAGES=()
declare -A DETECTED_FINGERPRINTS=()
declare -A DETECTED_VERSIONS=()

show_help() {
    cat <<EOF
Usage: scripts/detect_updates.sh [options]

Options:
  --package <pkgname-or-path>          Limit detection to one package
  --state-file <path>                  Detector state file (default: ${STATE_FILE})
  --cache-policy <normal|refresh>      Compare with state or only refresh it
  --dispatch-policy <auto|changed-only|selected>
                                       Auto-select manual packages, select only changed packages,
                                       or always select the requested package
  -h, --help                           Show this help
EOF
}

json_escape() {
    local value=$1

    value=${value//\\/\\\\}
    value=${value//"/\\"}
    value=${value//$'\n'/ }
    value=${value//$'\r'/ }
    printf '%s' "$value"
}

collect_packages() {
    local definition_file
    local package_dir

    PACKAGES=()
    while IFS= read -r definition_file; do
        package_dir=$(dirname "$definition_file")
        package_dir=${package_dir#./}
        PACKAGES+=("$package_dir")
    done < <(discover_package_definition_files packages)
}

validate_policy() {
    case "$CACHE_POLICY" in
        normal|refresh) ;;
        *) die "Unsupported cache policy: $CACHE_POLICY" ;;
    esac

    case "$DISPATCH_POLICY" in
        auto|changed-only|selected) ;;
        *) die "Unsupported dispatch policy: $DISPATCH_POLICY" ;;
    esac

    if [ "$DISPATCH_POLICY" = selected ] && [ -z "$PACKAGE_FILTER" ]; then
        die "dispatch-policy=selected requires --package"
    fi
}

effective_dispatch_policy() {
    if [ "$DISPATCH_POLICY" != auto ]; then
        printf '%s' "$DISPATCH_POLICY"
        return 0
    fi

    if [ -n "$PACKAGE_FILTER" ]; then
        printf 'selected'
    else
        printf 'changed-only'
    fi
}

load_previous_state() {
    local package
    local fingerprint
    local version
    local detected_at

    [ -f "$STATE_FILE" ] || return 0

    while IFS=$'\t' read -r package fingerprint version detected_at; do
        [ -n "$package" ] || continue
        PREVIOUS_FINGERPRINTS["$package"]=$fingerprint
        PREVIOUS_LINES["$package"]=$(printf '%s\t%s\t%s\t%s' "$package" "$fingerprint" "$version" "$detected_at")
    done < "$STATE_FILE"
}

detection_fingerprint() {
    local var

    printf 'PKGNAME=%s\n' "$PKGNAME"
    printf 'PACKAGE_SPEC_VERSION=%s\n' "$PACKAGE_SPEC_VERSION"
    printf 'UPSTREAM_TYPE=%s\n' "$UPSTREAM_TYPE"
    printf 'RESOLVED_VERSION=%s\n' "$RESOLVED_VERSION"
    printf 'PACKAGE_DEFINITION=%s\n' "$(package_definition_digest)"
    printf 'PACKAGE_FRAMEWORK=%s\n' "$(package_framework_digest)"
    printf 'BINARY_RELEASE_ENABLED=%s\n' "${BINARY_RELEASE_ENABLED:-false}"
    printf 'BINARY_RELEASE_REV=%s\n' "${BINARY_RELEASE_REV:-}"

    while IFS= read -r var; do
        case "$var" in
            GITHUB_RELEASE_TAG|RESOLVED_SOURCE_URL_*|STATE_*|UPSTREAM_ASSET_NAME_*|BINARY_RELEASE_ASSET_*)
                printf '%s=%s\n' "$var" "${!var}"
                ;;
        esac
    done < <(compgen -A variable | sort)
}

hash_file_list() {
    local file
    local relative_path
    local digest

    for file in "$@"; do
        [ -f "$file" ] || continue
        relative_path=${file#"$REPO_ROOT"/}
        digest=$(sha256sum "$file" | cut -d' ' -f1)
        printf '%s\t%s\n' "$relative_path" "$digest"
    done | sha256sum | cut -d' ' -f1
}

package_definition_digest() {
    local files=()
    local file
    local definition_path

    definition_path=$(package_definition_path "$PACKAGE_DIR") || die "PackageSpec definition not found in ${PACKAGE_DIR}"
    files+=("$definition_path")
    [ -f "${PACKAGE_DIR}/hooks.sh" ] && files+=("${PACKAGE_DIR}/hooks.sh")

    if [ -d "${PACKAGE_DIR}/files" ]; then
        while IFS= read -r file; do
            files+=("$file")
        done < <(find "${PACKAGE_DIR}/files" -type f | sort)
    fi

    hash_file_list "${files[@]}"
}

package_framework_digest() {
    local files=(
        "${SCRIPT_DIR}/aurpkg.py"
        "${SCRIPT_DIR}/auto_update.sh"
        "${SCRIPT_DIR}/test_package.sh"
    )
    local file

    while IFS= read -r file; do
        files+=("$file")
    done < <(find "${SCRIPT_DIR}/lib" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) | sort)

    hash_file_list "${files[@]}"
}

detect_package() {
    local package=$1

    (
        cd "$REPO_ROOT"
        load_package_spec "$package"
        load_package_hooks
        dispatch_upstream_resolution >&2

        local fingerprint
        fingerprint=$(detection_fingerprint | sha256sum | cut -d' ' -f1)

        printf '%s\t%s\t%s\n' \
            "$package" \
            "$fingerprint" \
            "$RESOLVED_VERSION"
    )
}

write_state() {
    local state_dir
    local tmp_file
    local package
    local detected_at

    state_dir=$(dirname "$STATE_FILE")
    mkdir -p "$state_dir"
    tmp_file=$(mktemp)
    detected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    for package in "${!PREVIOUS_LINES[@]}"; do
        if [ -z "${PROCESSED_PACKAGES[$package]:-}" ]; then
            printf '%s\n' "${PREVIOUS_LINES[$package]}" >> "$tmp_file"
        fi
    done

    for package in "${PACKAGES[@]}"; do
        [ -n "${DETECTED_FINGERPRINTS[$package]:-}" ] || continue
        printf '%s\t%s\t%s\t%s\n' \
            "$package" \
            "${DETECTED_FINGERPRINTS[$package]}" \
            "${DETECTED_VERSIONS[$package]}" \
            "$detected_at" >> "$tmp_file"
    done

    sort "$tmp_file" > "$STATE_FILE"
    rm -f "$tmp_file"
}

render_matrix_json() {
    local json='{"package":['
    local separator=''
    local package

    for package in "${CHANGED_PACKAGES[@]}"; do
        json+="${separator}\"$(json_escape "$package")\""
        separator=','
    done

    json+=']}'
    printf '%s' "$json"
}

main() {
    local package
    local result
    local fingerprint
    local version
    local previous_fingerprint
    local dispatch_policy
    local should_dispatch=false
    local matrix_json

    while [ "$#" -gt 0 ]; do
        case $1 in
            --package)
                shift || die "Missing value for --package"
                PACKAGE_FILTER=$1
                ;;
            --state-file)
                shift || die "Missing value for --state-file"
                STATE_FILE=$1
                ;;
            --cache-policy)
                shift || die "Missing value for --cache-policy"
                CACHE_POLICY=$1
                ;;
            --dispatch-policy)
                shift || die "Missing value for --dispatch-policy"
                DISPATCH_POLICY=$1
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                die "Unknown detect-updates parameter: $1"
                ;;
        esac
        shift || true
    done

    cd "$REPO_ROOT"
    validate_policy
    dispatch_policy=$(effective_dispatch_policy)
    load_previous_state

    if [ -n "$PACKAGE_FILTER" ]; then
        PACKAGES=("$(resolve_package_dir_input "$PACKAGE_FILTER")")
    else
        collect_packages
    fi

    for package in "${PACKAGES[@]}"; do
        printf '==> Detecting upstream state for %s\n' "$package" >&2
        result=$(detect_package "$package")
        IFS=$'\t' read -r package fingerprint version <<< "$result"

        PROCESSED_PACKAGES["$package"]=true
        DETECTED_FINGERPRINTS["$package"]=$fingerprint
        DETECTED_VERSIONS["$package"]=$version

        previous_fingerprint=${PREVIOUS_FINGERPRINTS[$package]:-}
        should_dispatch=false
        if [ "$dispatch_policy" = selected ]; then
            should_dispatch=true
        elif [ "$CACHE_POLICY" = refresh ]; then
            should_dispatch=false
        elif [ -z "$previous_fingerprint" ] || [ "$fingerprint" != "$previous_fingerprint" ]; then
            should_dispatch=true
        fi

        if [ "$should_dispatch" = true ]; then
            CHANGED_PACKAGES+=("$package")
        fi
    done

    write_state
    matrix_json=$(render_matrix_json)

    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "matrix=${matrix_json}" >> "$GITHUB_OUTPUT"
        if [ "${#CHANGED_PACKAGES[@]}" -gt 0 ]; then
            echo "has_packages=true" >> "$GITHUB_OUTPUT"
        else
            echo "has_packages=false" >> "$GITHUB_OUTPUT"
        fi
        echo "state_file=${STATE_FILE}" >> "$GITHUB_OUTPUT"
        log_info "Detected ${#CHANGED_PACKAGES[@]} package(s) to dispatch: ${matrix_json}"
    else
        if [ "${#CHANGED_PACKAGES[@]}" -gt 0 ]; then
            printf '%s\n' "${CHANGED_PACKAGES[@]}"
        fi
    fi
}

main "$@"
