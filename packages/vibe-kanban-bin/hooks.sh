#!/bin/bash

resolve_binary_tag_from_npm_package() {
    local tgz_path=$1
    local candidate
    local tag

    while IFS= read -r candidate; do
        case "$candidate" in
            package/bin/*.js|package/dist/*.js|package/*.js)
                tag=$(tar -xOf "$tgz_path" "$candidate" 2>/dev/null \
                    | grep 'BINARY_TAG' \
                    | sed -nE 's/.*BINARY_TAG[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
                    | head -n 1 || true)
                if [ -n "$tag" ]; then
                    printf '%s' "$tag"
                    return 0
                fi
                ;;
        esac
    done < <(tar -tzf "$tgz_path")
}

is_valid_binary_tag() {
    local tag=$1
    local version_re=${RESOLVED_VERSION//./\\.}

    [[ "$tag" =~ ^v${version_re}-[0-9]{14}$ ]]
}

resolve_upstream_state() {
    require_cmd curl
    require_cmd tar

    local manifest_url="https://npm-cdn.vibekanban.com/binaries/manifest.json"
    local response
    response=$(fetch_url_text_with_retry "$manifest_url") || die "Failed to fetch manifest from ${manifest_url}"

    RESOLVED_VERSION=$(printf '%s' "$response" | grep '"latest":' | sed -E 's/.*"latest": "([^"]+)".*/\1/' | head -n 1 || true)
    [ -n "$RESOLVED_VERSION" ] || die "Could not extract latest version from Vibe Kanban manifest"

    local npm_url="https://registry.npmjs.org/vibe-kanban/-/vibe-kanban-${RESOLVED_VERSION}.tgz"
    local tmp_tgz
    tmp_tgz=$(mktemp)
    trap 'rm -f "$tmp_tgz"' RETURN

    if curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "$npm_url" -o "$tmp_tgz" 2>/dev/null; then
        STATE_BINARY_TAG=$(resolve_binary_tag_from_npm_package "$tmp_tgz")
        is_valid_binary_tag "$STATE_BINARY_TAG" || STATE_BINARY_TAG=""
    fi

    if [ -z "$STATE_BINARY_TAG" ]; then
        STATE_BINARY_TAG=$(curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -H "User-Agent: aur-packages-ci" "https://github.com/BloopAI/vibe-kanban/tags" 2>/dev/null \
            | grep -oE "v${RESOLVED_VERSION}-[0-9]{14}" \
            | sort -u \
            | tail -n 1 || true)
    fi

    if [ -z "$STATE_BINARY_TAG" ] && [ "$RESOLVED_VERSION" = "$AUR_CURRENT_VER" ] && [ -f "${AUR_REPO_DIR}/PKGBUILD" ]; then
        STATE_BINARY_TAG=$(pkgbuild_var_from_file "${AUR_REPO_DIR}/PKGBUILD" "_binary_tag")
        is_valid_binary_tag "$STATE_BINARY_TAG" || STATE_BINARY_TAG=""
    fi

    if [ -z "$STATE_BINARY_TAG" ]; then
        die "Failed to resolve Vibe Kanban BINARY_TAG"
    fi

    is_valid_binary_tag "$STATE_BINARY_TAG" || die "Invalid Vibe Kanban BINARY_TAG: ${STATE_BINARY_TAG:-<empty>}"

    RESOLVED_SOURCE_URL_X86_64="https://npm-cdn.vibekanban.com/binaries/${STATE_BINARY_TAG}/linux-x64/vibe-kanban.zip"
}
