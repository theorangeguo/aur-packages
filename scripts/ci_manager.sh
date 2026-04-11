#!/bin/bash
set -e

COMMAND=$1
shift || true

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

case "$COMMAND" in
    discover)
        PACKAGES=()
        while IFS= read -r file; do
            dir=$(dirname "$file")
            dir=${dir#./}
            PACKAGES+=("$dir")
        done < <(find . -maxdepth 2 -name package.conf | sort)

        if [ -z "$GITHUB_OUTPUT" ]; then
            if [ "${#PACKAGES[@]}" -gt 0 ]; then
                printf '%s\n' "${PACKAGES[@]}"
            fi
        else
            if ! command -v jq >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y jq || true
            fi

            count=${#PACKAGES[@]}
            if [ "$count" -gt 0 ]; then
                json_array=$(printf '%s\n' "${PACKAGES[@]}" | jq -R . | jq -sc .)
            else
                json_array='[]'
            fi

            echo "matrix={\"package\": $json_array}" >> "$GITHUB_OUTPUT"

            if [ "$count" -gt 0 ]; then
                echo "has_packages=true" >> "$GITHUB_OUTPUT"
            else
                echo "has_packages=false" >> "$GITHUB_OUTPUT"
            fi

            log "Discovered $count packages: $json_array"
        fi
        ;;

    install)
        log "Installing dependencies..."
        if [ -f /etc/arch-release ]; then
            pacman -Syu --noconfirm git openssh pacman-contrib sudo curl jq
        else
            log "Not an Arch system. Skipping pacman install. Ensure dependencies are met manually."
        fi
        ;;

    setup_user)
        log "Setting up builder user..."
        if ! id -u builder >/dev/null 2>&1; then
            useradd -m builder
            echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
            chown -R builder:builder .
        else
            log "User 'builder' already exists."
        fi
        ;;

    run_update)
        PKG_DIR=$1
        shift || true
        ARGS=("$@")

        if [[ ! "$PKG_DIR" =~ ^(\./)?[a-zA-Z0-9._-]+$ ]]; then
            echo "!! ERROR: Invalid package directory name: $PKG_DIR"
            exit 1
        fi

        PKG_DIR=${PKG_DIR#./}

        [ -f "$PKG_DIR/package.conf" ] || {
            echo "!! ERROR: package.conf not found in $PKG_DIR"
            exit 1
        }

        chmod +x scripts/auto_update.sh

        if [ "$(id -u)" -eq 0 ]; then
            log "Running as root, switching to 'builder' user..."
            SAFE_PKG_DIR=$(printf %q "$PKG_DIR")
            SAFE_ARGS=""
            if [ "${#ARGS[@]}" -gt 0 ]; then
                SAFE_ARGS=$(printf ' %q' "${ARGS[@]}")
            fi
            CMD="export CI='$CI'; \
                 export AUR_USERNAME='$AUR_USERNAME'; \
                 export AUR_EMAIL='$AUR_EMAIL'; \
                 export AUR_SSH_PRIVATE_KEY='$AUR_SSH_PRIVATE_KEY'; \
                 bash scripts/auto_update.sh $SAFE_PKG_DIR$SAFE_ARGS"
            su builder -c "$CMD"
        else
            log "Running as current user ($(whoami))..."
            bash scripts/auto_update.sh "$PKG_DIR" "${ARGS[@]}"
        fi
        ;;

    run_test)
        PKG_DIR=$1
        shift || true

        if [[ ! "$PKG_DIR" =~ ^(\./)?[a-zA-Z0-9._-]+$ ]]; then
            echo "!! ERROR: Invalid package directory name: $PKG_DIR"
            exit 1
        fi

        PKG_DIR=${PKG_DIR#./}

        [ -f "$PKG_DIR/package.conf" ] || {
            echo "!! ERROR: package.conf not found in $PKG_DIR"
            exit 1
        }

        chmod +x scripts/test_package.sh

        if [ "$RUN_TEST_DIRECT" = "true" ] || [ "$CI" = "true" ]; then
            log "Running install test directly in current Arch environment..."
            bash scripts/test_package.sh "$PKG_DIR"
        else
            RUNTIME=$(detect_container_runtime) || {
                echo "!! ERROR: docker or podman is required for local package tests"
                exit 1
            }

            log "Running install test in ephemeral ${RUNTIME} container..."
            ${RUNTIME} run --rm \
                -v "$PWD:/src:ro" \
                archlinux:base-devel \
                bash -lc "set -e && mkdir -p /work && cp -a /src/. /work/ && cd /work && chmod +x scripts/ci_manager.sh scripts/test_package.sh && ./scripts/ci_manager.sh install && ./scripts/ci_manager.sh setup_user && RUN_TEST_DIRECT=true ./scripts/ci_manager.sh run_test $(printf %q "$PKG_DIR")"
        fi
        ;;

    *)
        echo "Usage: $0 {discover|install|setup_user|run_update <pkg> [args]|run_test <pkg>}"
        exit 1
        ;;
esac
