#!/bin/bash

resolve_upstream_state() {
    require_cmd curl
    require_cmd tar

    local manifest_url="https://npm-cdn.vibekanban.com/binaries/manifest.json"
    local response
    response=$(curl -fsSL "$manifest_url") || die "Failed to fetch manifest from ${manifest_url}"

    RESOLVED_VERSION=$(printf '%s' "$response" | grep '"latest":' | sed -E 's/.*"latest": "([^"]+)".*/\1/' | head -n 1)
    [ -n "$RESOLVED_VERSION" ] || die "Could not extract latest version from Vibe Kanban manifest"

    local npm_url="https://registry.npmjs.org/vibe-kanban/-/vibe-kanban-${RESOLVED_VERSION}.tgz"
    local tmp_tgz
    tmp_tgz=$(mktemp)
    trap 'rm -f "$tmp_tgz"' RETURN

    if curl -fsSL "$npm_url" -o "$tmp_tgz" 2>/dev/null; then
        STATE_BINARY_TAG=$(tar -xOf "$tmp_tgz" package/bin/download.js 2>/dev/null | grep 'BINARY_TAG =' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)
    fi

    if [ -z "$STATE_BINARY_TAG" ]; then
        STATE_BINARY_TAG=$(curl -fsSL -H "User-Agent: aur-packages-ci" "https://github.com/BloopAI/vibe-kanban/tags" 2>/dev/null \
            | grep -oE "v${RESOLVED_VERSION}-[0-9]{14}" \
            | sort -u \
            | tail -n 1)
    fi

    if [ -z "$STATE_BINARY_TAG" ] && [ "$RESOLVED_VERSION" = "$AUR_CURRENT_VER" ] && [ -f "${AUR_REPO_DIR}/PKGBUILD" ]; then
        STATE_BINARY_TAG=$(pkgbuild_var_from_file "${AUR_REPO_DIR}/PKGBUILD" "_binary_tag")
    fi

    if [ -z "$STATE_BINARY_TAG" ]; then
        die "Failed to resolve Vibe Kanban BINARY_TAG"
    fi

    [ -n "$STATE_BINARY_TAG" ] || die "Could not extract BINARY_TAG from Vibe Kanban npm package"

    RESOLVED_SOURCE_URL_X86_64="https://npm-cdn.vibekanban.com/binaries/${STATE_BINARY_TAG}/linux-x64/vibe-kanban.zip"
}
