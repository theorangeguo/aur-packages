#!/bin/bash

resolve_upstream_state() {
    require_cmd curl
    require_cmd jq
    require_cmd sort
    require_cmd tail

    local repo="orange-guo/aur-packages"
    local tag_prefix="zellij-no-mouse-resize-bin-v"
    local asset_name="zellij-no-mouse-resize-bin-x86_64-unknown-linux-gnu.tar.gz"
    local api_url="https://api.github.com/repos/${repo}/releases?per_page=100"
    local token=${GITHUB_TOKEN:-${GH_TOKEN:-}}
    local auth_args=()
    local release_records
    local latest_record
    local latest_tag
    local asset_url

    if [ -n "$token" ]; then
        auth_args=(-H "Authorization: Bearer ${token}")
    fi

    release_records=$(curl -fsSL \
        --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: aur-packages-ci" \
        "${auth_args[@]}" \
        "$api_url" \
        | jq -r --arg prefix "$tag_prefix" --arg asset "$asset_name" '
            .[]
            | select((.tag_name // "") | startswith($prefix)) as $release
            | $release.assets[]?
            | select((.name // "") == $asset)
            | [$release.tag_name, .browser_download_url]
            | @tsv
        ') || die "Failed to query ${repo} releases"

    [ -n "$release_records" ] || die "No ${asset_name} release asset found in ${repo}"

    latest_record=$(printf '%s\n' "$release_records" | sort -t $'\t' -k1,1V | tail -n 1)
    latest_tag=${latest_record%%$'\t'*}
    asset_url=${latest_record#*$'\t'}

    [ -n "$latest_tag" ] || die "Failed to resolve zellij-no-mouse-resize-bin release tag"
    [ -n "$asset_url" ] || die "Failed to resolve zellij-no-mouse-resize-bin asset URL"

    RESOLVED_VERSION=${latest_tag#"$tag_prefix"}
    [ -n "$RESOLVED_VERSION" ] || die "Failed to resolve zellij-no-mouse-resize-bin version"

    RESOLVED_SOURCE_URL_X86_64=$asset_url
}
