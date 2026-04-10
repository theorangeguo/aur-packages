#!/bin/bash

resolve_github_release_assets() {
    require_cmd curl
    require_cmd jq

    local api_url
    if [ "$UPSTREAM_ALLOW_PRERELEASE" = "true" ]; then
        api_url="https://api.github.com/repos/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases"
    else
        api_url="https://api.github.com/repos/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases/latest"
    fi

    local response
    if ! response=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: aur-packages-ci" \
        "$api_url" 2>/dev/null); then
        log_info "GitHub API unavailable; falling back to release page scraping."
        resolve_github_release_assets_via_web
        return 0
    fi

    local release_json=$response
    if [ "$UPSTREAM_ALLOW_PRERELEASE" = "true" ]; then
        release_json=$(printf '%s' "$response" | jq 'first')
    fi

    local latest_tag
    latest_tag=$(printf '%s' "$release_json" | jq -r '.tag_name // empty')
    [ -n "$latest_tag" ] || die "Could not extract tag_name from GitHub release metadata"

    RESOLVED_VERSION=$latest_tag
    if [ -n "$UPSTREAM_TAG_PREFIX" ] && [[ "$RESOLVED_VERSION" == "${UPSTREAM_TAG_PREFIX}"* ]]; then
        RESOLVED_VERSION=${RESOLVED_VERSION#"$UPSTREAM_TAG_PREFIX"}
    fi

    resolve_github_asset_for_arch x86_64 "$release_json"
    resolve_github_asset_for_arch aarch64 "$release_json"
}

resolve_github_release_assets_via_web() {
    local latest_url
    latest_url=$(curl -fsSLI \
        -H "User-Agent: aur-packages-ci" \
        -o /dev/null \
        -w '%{url_effective}' \
        "https://github.com/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases/latest") || die "Failed to resolve latest GitHub release URL"

    local latest_tag=${latest_url##*/}
    [ -n "$latest_tag" ] || die "Could not determine latest GitHub release tag"

    RESOLVED_VERSION=$latest_tag
    if [ -n "$UPSTREAM_TAG_PREFIX" ] && [[ "$RESOLVED_VERSION" == "${UPSTREAM_TAG_PREFIX}"* ]]; then
        RESOLVED_VERSION=${RESOLVED_VERSION#"$UPSTREAM_TAG_PREFIX"}
    fi

    local assets_url="https://github.com/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases/expanded_assets/${latest_tag}"
    local assets_html
    assets_html=$(curl -fsSL -H "User-Agent: aur-packages-ci" "$assets_url") || die "Failed to fetch GitHub expanded assets page"

    mapfile -t GITHUB_RELEASE_WEB_ASSET_URLS < <(
        printf '%s' "$assets_html" \
            | grep -oE 'href="/[^"]+/releases/download/[^"]+"' \
            | sed -E 's/^href="//; s/"$//' \
            | sed 's#^#https://github.com#'
    )

    [ "${#GITHUB_RELEASE_WEB_ASSET_URLS[@]}" -gt 0 ] || die "No downloadable assets found on GitHub expanded assets page"

    resolve_github_web_asset_for_arch x86_64
    resolve_github_web_asset_for_arch aarch64
}

resolve_github_asset_for_arch() {
    local arch=$1
    local release_json=$2

    local suffix
    suffix=$(arch_var_suffix "$arch")
    local selector_var="ASSET_SELECTOR_${suffix}"
    local selector=${!selector_var}

    [ -n "$selector" ] || return 0

    local download_url
    download_url=$(printf '%s' "$release_json" | jq -r --arg regex "$selector" '
        .assets[]
        | select((.name // "") | test($regex))
        | .browser_download_url
        ' | head -n 1)

    [ -n "$download_url" ] || die "Failed to match GitHub release asset for ${arch} using regex: ${selector}"

    local resolved_var="RESOLVED_SOURCE_URL_${suffix}"
    printf -v "$resolved_var" '%s' "$download_url"
}

resolve_github_web_asset_for_arch() {
    local arch=$1

    local suffix
    suffix=$(arch_var_suffix "$arch")
    local selector_var="ASSET_SELECTOR_${suffix}"
    local selector=${!selector_var}

    [ -n "$selector" ] || return 0

    local asset_url
    for asset_url in "${GITHUB_RELEASE_WEB_ASSET_URLS[@]}"; do
        local asset_name=${asset_url##*/}
        if [[ "$asset_name" =~ $selector ]]; then
            local resolved_var="RESOLVED_SOURCE_URL_${suffix}"
            printf -v "$resolved_var" '%s' "$asset_url"
            return 0
        fi
    done

    die "Failed to match GitHub release asset for ${arch} using regex: ${selector}"
}
