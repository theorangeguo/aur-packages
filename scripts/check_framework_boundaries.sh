#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
SELF_PATH=$(realpath "${BASH_SOURCE[0]}")

failures=0
package_names=()
shared_files=()
declare -A seen_package_names=()

add_failure() {
    printf '!! ERROR: %s\n' "$*" >&2
    failures=$((failures + 1))
}

load_package_names() {
    local config_path
    local line
    local name

    while IFS= read -r config_path; do
        add_package_name "$(basename "$(dirname "$config_path")")"

        while IFS= read -r line; do
            case "$line" in
                PKGNAME=*)
                    name=${line#PKGNAME=}
                    name=${name%%#*}
                    name=${name//[[:space:]]/}
                    name=${name%\'}
                    name=${name#\'}
                    name=${name%\"}
                    name=${name#\"}
                    add_package_name "$name"
                    break
                    ;;
            esac
        done < "$config_path"
    done < <(find "${REPO_ROOT}/packages" -mindepth 2 -maxdepth 2 -name package.conf -type f | sort)
}

add_package_name() {
    local name=$1

    [ -n "$name" ] || return 0
    [ -n "${seen_package_names[$name]+seen}" ] && return 0

    seen_package_names[$name]=true
    package_names+=("$name")
}

regex_escape() {
    printf '%s' "$1" | sed 's/[][(){}.^$*+?|\\]/\\&/g'
}

load_shared_files() {
    local file_path

    while IFS= read -r file_path; do
        [ "$(realpath "$file_path")" = "$SELF_PATH" ] && continue
        shared_files+=("$file_path")
    done < <(
        find "${REPO_ROOT}/scripts" "${REPO_ROOT}/.github/workflows" \
            -type f \
            \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' \) \
            | sort
    )
}

check_package_names_absent_from_shared_code() {
    local package_name
    local file_path
    local match_output
    local escaped_name
    local package_name_pattern

    for package_name in "${package_names[@]}"; do
        [ -n "$package_name" ] || continue
        escaped_name=$(regex_escape "$package_name")
        package_name_pattern="(^|[^A-Za-z0-9._-])${escaped_name}([^A-Za-z0-9._-]|$)"

        for file_path in "${shared_files[@]}"; do
            match_output=$(grep -En -- "$package_name_pattern" "$file_path" || true)
            if [ -n "$match_output" ]; then
                add_failure "Package-specific name '${package_name}' found in shared automation: ${file_path#"${REPO_ROOT}/"}"
                printf '%s\n' "$match_output" >&2
            fi
        done
    done
}

check_pkgname_branching() {
    local file_path
    local match_output
    local patterns=(
        'case[[:space:]]+["'"'"']?\$\{?PKGNAME\}?'
        'if[[:space:]].*\$\{?PKGNAME\}?.*(=|==|!=)[[:space:]]*["'"'"']?[A-Za-z0-9._+-]+'
    )
    local pattern

    for file_path in "${shared_files[@]}"; do
        for pattern in "${patterns[@]}"; do
            match_output=$(grep -En -- "$pattern" "$file_path" || true)
            if [ -n "$match_output" ]; then
                add_failure "Potential package-name branching found in shared automation: ${file_path#"${REPO_ROOT}/"}"
                printf '%s\n' "$match_output" >&2
            fi
        done
    done
}

main() {
    cd "$REPO_ROOT"

    load_package_names
    load_shared_files

    check_package_names_absent_from_shared_code
    check_pkgname_branching

    if [ "$failures" -gt 0 ]; then
        cat >&2 <<'EOF'

Shared automation must stay package-agnostic.
Move package-specific behavior into package.conf, package-local hooks.sh, package-local files/, or a new generic framework feature.
See docs/PACKAGE_FRAMEWORK.md.
EOF
        exit 1
    fi

    printf 'Framework boundary check passed.\n'
}

main "$@"
