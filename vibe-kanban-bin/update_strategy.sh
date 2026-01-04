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

    # Extract version: 0.0.143
    local version=$(echo "$response" | grep '"latest":' | sed -E 's/.*"latest": "([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        log_error "Could not extract version from manifest."
        return 1
    fi

    # Now we need to find the BINARY_TAG (with timestamp) to update PKGBUILD.
    # The manifest only gives us the version (e.g. 0.0.143).
    # We must fetch the NPM package to find the BINARY_TAG in bin/download.js.

    log_info "Fetching NPM package to discover binary tag..." >&2
    local npm_url="https://registry.npmjs.org/vibe-kanban/-/vibe-kanban-${version}.tgz"
    local tmp_tgz=$(mktemp)

    if curl -sSL "$npm_url" -o "$tmp_tgz"; then
        # Extract bin/download.js to stdout and grep the tag
        # BINARY_TAG = "v0.0.143-20251229180119";
        local binary_tag=$(tar -xOf "$tmp_tgz" package/bin/download.js | grep 'BINARY_TAG =' | sed -E 's/.*"([^"]+)".*/\1/')

        rm -f "$tmp_tgz"

        if [ -n "$binary_tag" ]; then
            log_info "Found binary tag: $binary_tag" >&2
            # Update _binary_tag in PKGBUILD immediately
            sed -i "s/^_binary_tag=.*/_binary_tag=$binary_tag/" PKGBUILD
        else
            log_error "Could not extract BINARY_TAG from download.js"
            # Don't fail the version check, but warn.
        fi
    else
        log_error "Failed to download NPM package."
        rm -f "$tmp_tgz"
    fi

    # Return the clean version number for auto_update.sh to handle pkgver
    echo "$version"
}
