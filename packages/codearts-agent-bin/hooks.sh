#!/bin/bash

resolve_upstream_state() {
    local download_page="https://codearts.huaweicloud.com/download.html"
    local html
    html=$(fetch_url_text_with_retry "$download_page") || die "Failed to fetch CodeArts download page: ${download_page}"

    # Extract deb download URLs for both x64 and arm64 architectures
    local url_x64
    local url_arm64
    url_x64=$(printf '%s\n' "$html" | grep -oE 'https://codearts-agent-obs-cdn\.huaweicloud\.com/codearts/ai/latest/codearts-agent-linux-x64-[^"'\'' >]+\.deb' | head -n 1)
    url_arm64=$(printf '%s\n' "$html" | grep -oE 'https://codearts-agent-obs-cdn\.huaweicloud\.com/codearts/ai/latest/codearts-agent-linux-arm64-[^"'\'' >]+\.deb' | head -n 1)

    [ -n "$url_x64" ] || die "Failed to find CodeArts Agent x64 deb URL in ${download_page}"
    [ -n "$url_arm64" ] || die "Failed to find CodeArts Agent arm64 deb URL in ${download_page}"

    local filename_x64="${url_x64##*/}"
    local filename_arm64="${url_arm64##*/}"

    local version_x64=""
    local version_arm64=""

    # Robust filename parsing: supports semantic version numbers with optional alphanumeric/build-id hashes
    local regex_x64='^codearts-agent-linux-x64-([0-9]+(\.[0-9]+)+)(-[A-Za-z0-9._]+)?\.deb$'
    local regex_arm64='^codearts-agent-linux-arm64-([0-9]+(\.[0-9]+)+)(-[A-Za-z0-9._]+)?\.deb$'

    if [[ "$filename_x64" =~ $regex_x64 ]]; then
        version_x64="${BASH_REMATCH[1]}"
    else
        die "Unexpected CodeArts Agent x64 deb filename format: ${filename_x64}"
    fi

    if [[ "$filename_arm64" =~ $regex_arm64 ]]; then
        version_arm64="${BASH_REMATCH[1]}"
    else
        die "Unexpected CodeArts Agent arm64 deb filename format: ${filename_arm64}"
    fi

    [ "$version_x64" = "$version_arm64" ] || die "CodeArts Agent versions mismatch: x64=${version_x64} vs arm64=${version_arm64}"

    # Cross-reference with changelog page if reachable (informational log only)
    local changelog_html
    local changelog_ver
    changelog_html=$(curl -fsSL --connect-timeout 5 "https://codearts.huaweicloud.com/changelog.html" 2>/dev/null || true)
    if [ -n "$changelog_html" ]; then
        changelog_ver=$(printf '%s\n' "$changelog_html" | grep -oE 'data-attr-version=v[0-9]+(\.[0-9]+)+' | head -n 1 | sed 's/data-attr-version=v//')
        if [ -n "$changelog_ver" ]; then
            log_info "Official changelog latest version: ${changelog_ver}"
        fi
    fi

    RESOLVED_VERSION="$version_x64"
    RESOLVED_SOURCE_URL_X86_64="$url_x64"
    RESOLVED_SOURCE_URL_AARCH64="$url_arm64"
}
