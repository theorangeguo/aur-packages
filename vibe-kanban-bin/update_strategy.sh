#!/bin/bash

check_upstream_version() {
    # Custom version check for vibe-kanban using their R2 manifest
    local manifest_url="https://npm-cdn.vibekanban.com/binaries/manifest.json"

    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed."
        return 1
    fi

    local response
    response=$(curl -sS "$manifest_url")

    if [ -z "$response" ]; then
        log_error "Empty response from manifest URL."
        return 1
    fi

    # Extract "latest": "v0.0.143-20251229180119"
    local full_tag=$(echo "$response" | grep '"latest":' | sed -E 's/.*"latest": "([^"]+)".*/\1/')

    if [ -z "$full_tag" ]; then
        log_error "Could not extract latest tag from manifest."
        return 1
    fi

    # full_tag example: v0.0.143-20251229180119
    # Extract version: 0.0.143
    local version=$(echo "$full_tag" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')

    if [ -z "$version" ]; then
        log_error "Could not extract version from tag: $full_tag"
        return 1
    fi

    # SIDE EFFECT: Update _tag in PKGBUILD immediately
    # We do this here because auto_update.sh only updates pkgver
    sed -i "s/^_tag=.*/_tag=\"$full_tag\"/" PKGBUILD

    # Return the clean version number for auto_update.sh to handle pkgver
    echo "$version"
}
