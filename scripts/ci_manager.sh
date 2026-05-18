#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "${1:-}" = install ] && ! command -v python3 >/dev/null 2>&1; then
    echo "==> [CI Manager] Installing dependencies..."
    if [ -f /etc/arch-release ]; then
        [ "$(id -u)" -eq 0 ] || { echo "!! ERROR: install must be run as root" >&2; exit 1; }

        if [ "${CI:-}" = true ] && command -v pacman-key >/dev/null 2>&1; then
            echo "==> [CI Manager] Initializing pacman keyring for CI..."
            pacman-key --init >/dev/null 2>&1 || { echo "!! ERROR: Failed to initialize pacman keyring" >&2; exit 1; }
        fi

        attempt=1
        while ! pacman -Syu --needed --noconfirm git openssh pacman-contrib sudo curl jq python; do
            [ "$attempt" -ge 3 ] && { echo "!! ERROR: Failed to install required Arch packages" >&2; exit 1; }
            echo "==> [CI Manager] pacman failed (attempt ${attempt}/3); retrying..."
            sleep $((attempt * 2))
            attempt=$((attempt + 1))
        done
    else
        echo "==> [CI Manager] Not an Arch system. Skipping pacman install. Ensure dependencies are met manually."
    fi
    exit 0
fi

exec python3 "${SCRIPT_DIR}/aurpkg.py" "$@"
