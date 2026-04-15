#!/bin/bash

resolve_upstream_state() {
    require_cmd git
    require_cmd awk
    require_cmd grep
    require_cmd sed
    require_cmd sort
    require_cmd tail

    local repo_url="${URL}.git"
    local tags

    tags=$(git ls-remote --tags --refs "$repo_url" 'refs/tags/0.20.*' \
        | awk '{print $2}' \
        | sed 's#refs/tags/##' \
        | grep -E '^0\.20\.[0-9]+$' \
        | sort -V) || die "Failed to query wlroots tags from ${repo_url}"

    RESOLVED_VERSION=$(printf '%s\n' "$tags" | tail -n 1)
    [ -n "$RESOLVED_VERSION" ] || die "Failed to resolve latest wlroots 0.20.x tag"

    RESOLVED_SOURCE_URL="git+${repo_url}#tag=${RESOLVED_VERSION}?signed"
}
