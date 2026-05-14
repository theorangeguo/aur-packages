#!/bin/bash

resolve_upstream_state() {
    require_cmd curl

    local latest_url
    local latest_tag

    latest_url=$(curl -fsSLI \
        --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
        -H "User-Agent: aur-packages-ci" \
        -o /dev/null \
        -w '%{url_effective}' \
        "https://github.com/zellij-org/zellij/releases/latest") \
        || die "Failed to resolve latest Zellij release URL"

    latest_tag=${latest_url##*/}
    [ -n "$latest_tag" ] || die "Failed to resolve latest Zellij release tag"

    RESOLVED_VERSION=${latest_tag#v}
    [ -n "$RESOLVED_VERSION" ] || die "Failed to resolve latest Zellij version"

    RESOLVED_SOURCE_URL="https://github.com/zellij-org/zellij/archive/refs/tags/${latest_tag}.tar.gz"
}
