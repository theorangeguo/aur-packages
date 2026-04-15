#!/bin/bash
set -e

COMMAND=${1:-}
shift || true

ARCH_BASE_DEVEL_IMAGE=${ARCH_BASE_DEVEL_IMAGE:-archlinux:base-devel@sha256:01bd0ee1c23c3dec1dcb0fce558150a222ee2ef0a3776404de33d0714bcefbb0}
PACKAGE_ROOT=packages

detect_container_runtime() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        printf 'docker'
        return 0
    fi

    if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        printf 'podman'
        return 0
    fi

    return 1
}

log() {
    echo "==> [CI Manager] $1"
}

die() {
    echo "!! ERROR: $1" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "$1 must be run as root"
}

retry_command() {
    local max_attempts=$1
    shift
    local attempt=1

    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            return 1
        fi

        log "Command failed (attempt ${attempt}/${max_attempts}); retrying..."
        sleep $((attempt * 2))
        attempt=$((attempt + 1))
    done
}

canonical_package_dir() {
    local input=$1
    local candidate

    [ -n "$input" ] || die "Package directory is required"
    input=${input#./}

    case "$input" in
        packages/*)
            [[ "$input" =~ ^packages/[a-zA-Z0-9._-]+$ ]] || die "Invalid package directory name: $input"
            candidate=$input
            ;;
        *)
            [[ "$input" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Invalid package directory name: $input"
            candidate="${PACKAGE_ROOT}/${input}"
            ;;
    esac

    [ -f "$candidate/package.conf" ] || die "package.conf not found in $candidate"
    printf '%s' "$candidate"
}

collect_all_packages() {
    PACKAGES=()

    [ -d "$PACKAGE_ROOT" ] || return 0

    while IFS= read -r file; do
        local dir
        dir=$(dirname "$file")
        dir=${dir#./}
        PACKAGES+=("$dir")
    done < <(find "$PACKAGE_ROOT" -mindepth 2 -maxdepth 2 -name package.conf | sort)
}

append_unique_package() {
    local package=$1
    local existing

    for existing in "${PACKAGES[@]}"; do
        [ "$existing" = "$package" ] && return 0
    done

    PACKAGES+=("$package")
}

discover_changed_packages() {
    local base_ref=$1
    local head_ref=$2
    local diff_output
    local changed_files=()
    local changed_file
    local candidate_dir

    PACKAGES=()
    git rev-parse --verify "${base_ref}^{commit}" >/dev/null 2>&1 || die "Unknown discovery base ref: $base_ref"
    git rev-parse --verify "${head_ref}^{commit}" >/dev/null 2>&1 || die "Unknown discovery head ref: $head_ref"

    diff_output=$(git diff --name-only --diff-filter=ACMR "$base_ref" "$head_ref") \
        || die "Failed to diff changed files between $base_ref and $head_ref"

    if [ -n "$diff_output" ]; then
        mapfile -t changed_files <<< "$diff_output"
    fi

    for changed_file in "${changed_files[@]}"; do
        [ -n "$changed_file" ] || continue

        case "$changed_file" in
            scripts/*|.github/workflows/*)
                collect_all_packages
                return 0
                ;;
        esac

        case "$changed_file" in
            packages/*/*)
                candidate_dir=$(printf '%s' "$changed_file" | cut -d/ -f1-2)
                ;;
            *)
                continue
                ;;
        esac

        [ -f "$candidate_dir/package.conf" ] || continue
        append_unique_package "$candidate_dir"
    done
}

render_discovery_json() {
    local json='['
    local separator=''
    local package

    for package in "${PACKAGES[@]}"; do
        json+="${separator}\"${package}\""
        separator=', '
    done

    json+=']'
    printf '%s' "$json"
}

run_discovery() {
    local package_filter=""
    local base_ref=""
    local head_ref=""

    while [ "$#" -gt 0 ]; do
        case $1 in
            --package)
                shift || die "Missing value for --package"
                package_filter=$1
                ;;
            --base-ref)
                shift || die "Missing value for --base-ref"
                base_ref=$1
                ;;
            --head-ref)
                shift || die "Missing value for --head-ref"
                head_ref=$1
                ;;
            *)
                die "Unknown discover parameter: $1"
                ;;
        esac
        shift || true
    done

    if [ -n "$base_ref" ] || [ -n "$head_ref" ]; then
        [ -n "$base_ref" ] && [ -n "$head_ref" ] || die "--base-ref and --head-ref must be provided together"
    fi

    if [ -n "$package_filter" ]; then
        PACKAGES=("$(canonical_package_dir "$package_filter")")
    elif [ -n "$base_ref" ] && [ -n "$head_ref" ]; then
        discover_changed_packages "$base_ref" "$head_ref"
    else
        collect_all_packages
    fi

    if [ -z "$GITHUB_OUTPUT" ]; then
        if [ "${#PACKAGES[@]}" -gt 0 ]; then
            printf '%s\n' "${PACKAGES[@]}"
        fi
        return 0
    fi

    local count=${#PACKAGES[@]}
    local json_array
    json_array=$(render_discovery_json)

    echo "matrix={\"package\": ${json_array}}" >> "$GITHUB_OUTPUT"

    if [ "$count" -gt 0 ]; then
        echo "has_packages=true" >> "$GITHUB_OUTPUT"
    else
        echo "has_packages=false" >> "$GITHUB_OUTPUT"
    fi

    log "Discovered $count packages: $json_array"
}

show_help() {
    cat <<EOF
Usage: $0 {discover [--package <pkgname-or-packages/pkgname> | --base-ref <ref> --head-ref <ref>]|install|setup_user|run_update <pkgname-or-packages/pkgname> [args]|run_test <pkgname-or-packages/pkgname>}
EOF
}

case "$COMMAND" in
    discover)
        run_discovery "$@"
        ;;

    install)
        log "Installing dependencies..."
        if [ -f /etc/arch-release ]; then
            require_root install
            retry_command 3 pacman -Syu --needed --noconfirm git openssh pacman-contrib sudo curl jq \
                || die "Failed to install required Arch packages"
        else
            log "Not an Arch system. Skipping pacman install. Ensure dependencies are met manually."
        fi
        ;;

    setup_user)
        require_root setup_user
        log "Setting up builder user..."
        if ! id -u builder >/dev/null 2>&1; then
            useradd -m builder
        else
            log "User 'builder' already exists."
        fi

        if [ ! -f /etc/sudoers.d/builder ]; then
            printf '%s\n' 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
            chmod 440 /etc/sudoers.d/builder
        fi
        ;;

    run_update)
        PKG_DIR=$1
        shift || true
        ARGS=("$@")
        PKG_DIR=$(canonical_package_dir "$PKG_DIR")

        chmod +x scripts/auto_update.sh

        if [ "$(id -u)" -eq 0 ]; then
            log "Running update pipeline as root..."
            CI="${CI:-}" \
            AUR_USERNAME="${AUR_USERNAME:-}" \
            AUR_EMAIL="${AUR_EMAIL:-}" \
            AUR_SSH_PRIVATE_KEY="${AUR_SSH_PRIVATE_KEY:-}" \
            bash scripts/auto_update.sh "$PKG_DIR" "${ARGS[@]}"
        else
            log "Running as current user ($(whoami))..."
            bash scripts/auto_update.sh "$PKG_DIR" "${ARGS[@]}"
        fi
        ;;

    run_test)
        PKG_DIR=$1
        shift || true
        PKG_DIR=$(canonical_package_dir "$PKG_DIR")

        chmod +x scripts/test_package.sh

        if [ "$RUN_TEST_DIRECT" = "true" ] || [ "$CI" = "true" ]; then
            log "Running install test directly in current Arch environment..."
            bash scripts/test_package.sh "$PKG_DIR"
        else
            RUNTIME=$(detect_container_runtime) || die "docker or podman is required for local package tests"

            log "Running install test in ephemeral ${RUNTIME} container..."
            ${RUNTIME} run --rm \
                -v "$PWD:/src:ro" \
                "$ARCH_BASE_DEVEL_IMAGE" \
                bash -lc "set -e && mkdir -p /work && cp -a /src/. /work/ && rm -rf /work/.git && cd /work && chmod +x scripts/ci_manager.sh scripts/test_package.sh && ./scripts/ci_manager.sh install && ./scripts/ci_manager.sh setup_user && RUN_TEST_DIRECT=true ./scripts/ci_manager.sh run_test $(printf %q "$PKG_DIR")"
        fi
        ;;

    *)
        show_help
        exit 1
        ;;
esac
