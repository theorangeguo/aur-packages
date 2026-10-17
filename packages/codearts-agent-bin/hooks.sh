#!/bin/bash

resolve_upstream_state() {
    local html
    local download_page="https://codearts.huaweicloud.com/download.html"

    html=$(fetch_url_text_with_retry "$download_page") || die "Failed to fetch CodeArts download page: ${download_page}"

    local url_x64
    local url_arm64
    url_x64=$(printf '%s\n' "$html" | grep -oE 'https://codearts-agent-obs-cdn\.huaweicloud\.com/codearts/ai/latest/codearts-agent-linux-x64-[0-9.]+-([0-9a-f]+)\.deb' | head -n 1)
    url_arm64=$(printf '%s\n' "$html" | grep -oE 'https://codearts-agent-obs-cdn\.huaweicloud\.com/codearts/ai/latest/codearts-agent-linux-arm64-[0-9.]+-([0-9a-f]+)\.deb' | head -n 1)

    [ -n "$url_x64" ] || die "Failed to find CodeArts Agent x64 deb URL in ${download_page}"
    [ -n "$url_arm64" ] || die "Failed to find CodeArts Agent arm64 deb URL in ${download_page}"

    local filename_x64="${url_x64##*/}"
    local filename_arm64="${url_arm64##*/}"

    local version_x64
    local version_arm64
    local hash_x64
    local hash_arm64

    if [[ "$filename_x64" =~ codearts-agent-linux-x64-([0-9.]+)-([0-9a-f]+)\.deb ]]; then
        version_x64="${BASH_REMATCH[1]}"
        hash_x64="${BASH_REMATCH[2]}"
    else
        die "Unexpected CodeArts Agent x64 deb filename format: ${filename_x64}"
    fi

    if [[ "$filename_arm64" =~ codearts-agent-linux-arm64-([0-9.]+)-([0-9a-f]+)\.deb ]]; then
        version_arm64="${BASH_REMATCH[1]}"
        hash_arm64="${BASH_REMATCH[2]}"
    else
        die "Unexpected CodeArts Agent arm64 deb filename format: ${filename_arm64}"
    fi

    [ "$version_x64" = "$version_arm64" ] || die "CodeArts Agent versions mismatch: x64=${version_x64} vs arm64=${version_arm64}"
    [ "$hash_x64" = "$hash_arm64" ] || die "CodeArts Agent commit hashes mismatch: x64=${hash_x64} vs arm64=${hash_arm64}"

    RESOLVED_VERSION="$version_x64"
    RESOLVED_SOURCE_URL_X86_64="$url_x64"
    RESOLVED_SOURCE_URL_AARCH64="$url_arm64"
}
