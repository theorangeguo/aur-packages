#!/bin/bash

GITHUB_API_FAILURE_REASON=""
GITHUB_RELEASE_TAG=""
GITHUB_RELEASE_WEB_ASSET_URLS=()

github_fetch_releases_json() {
    local page=1
    local response_file
    local combined_file
    local next_combined_file
    local count

    combined_file=$(mktemp)
    printf '[]' > "$combined_file"

    while true; do
        response_file=$(mktemp)
        if ! github_api_request_to_file "https://api.github.com/repos/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases?per_page=100&page=${page}" "$response_file"; then
            rm -f "$response_file" "$combined_file"
            die "GitHub API unavailable (${GITHUB_API_FAILURE_REASON:-unknown reason}); cannot resolve release family ${UPSTREAM_RELEASE_TAG_PREFIX}."
        fi

        count=$(jq 'length' "$response_file")
        if [ "$count" -eq 0 ]; then
            rm -f "$response_file"
            break
        fi

        next_combined_file=$(mktemp)
        jq -s '.[0] + .[1]' "$combined_file" "$response_file" > "$next_combined_file"
        mv "$next_combined_file" "$combined_file"
        rm -f "$response_file"
        page=$((page + 1))
    done

    cat "$combined_file"
    rm -f "$combined_file"
}

github_exact_asset_name_for_arch() {
    local arch=$1
    local suffix
    suffix=$(arch_var_suffix "$arch")
    local exact_var="UPSTREAM_ASSET_NAME_${suffix}"
    local template=${!exact_var}

    [ -n "$template" ] || return 0

    local pkgname=$PKGNAME
    local pkgver=$RESOLVED_VERSION
    local carch=$arch
    expand_template "$template"
}

github_asset_selector_for_arch() {
    local arch=$1
    local suffix
    suffix=$(arch_var_suffix "$arch")
    local selector_var="ASSET_SELECTOR_${suffix}"
    printf '%s' "${!selector_var}"
}

github_asset_match_description_for_arch() {
    local arch=$1
    local exact_name
    local selector

    exact_name=$(github_exact_asset_name_for_arch "$arch")
    if [ -n "$exact_name" ]; then
        printf 'exact asset name: %s' "$exact_name"
        return 0
    fi

    selector=$(github_asset_selector_for_arch "$arch")
    if [ -n "$selector" ]; then
        printf 'regex: %s' "$selector"
        return 0
    fi

    printf '<none>'
}

github_arch_has_asset_matcher() {
    local arch=$1
    local exact_name
    local selector

    exact_name=$(github_exact_asset_name_for_arch "$arch")
    selector=$(github_asset_selector_for_arch "$arch")
    [ -n "$exact_name" ] || [ -n "$selector" ]
}

github_api_request_to_file() {
    local api_url=$1
    local output_file=$2
    local error_file
    local http_code
    local curl_status
    local curl_error
    local token=${GITHUB_TOKEN:-${GH_TOKEN:-}}
    local auth_args=()

    if [ -n "$token" ]; then
        auth_args=(-H "Authorization: Bearer ${token}")
    fi

    error_file=$(mktemp)
    set +e
    http_code=$(curl -sS -L \
        --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: aur-packages-ci" \
        "${auth_args[@]}" \
        -o "$output_file" \
        -w '%{http_code}' \
        "$api_url" 2>"$error_file")
    curl_status=$?
    set -e

    if [ "$curl_status" -ne 0 ]; then
        curl_error=$(<"$error_file")
        curl_error=${curl_error//$'\n'/ }
        GITHUB_API_FAILURE_REASON="curl exit ${curl_status}"
        if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
            GITHUB_API_FAILURE_REASON+=", HTTP ${http_code}"
        fi
        if [ -n "$curl_error" ]; then
            GITHUB_API_FAILURE_REASON+=": ${curl_error}"
        fi
        rm -f "$error_file"
        return 1
    fi

    rm -f "$error_file"

    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        local api_message
        api_message=$(jq -r '.message // empty' "$output_file" 2>/dev/null || true)
        GITHUB_API_FAILURE_REASON="HTTP ${http_code}"
        if [ -n "$api_message" ]; then
            GITHUB_API_FAILURE_REASON+=": ${api_message}"
        fi
        return 1
    fi
}

github_fetch_latest_release_url() {
    local url=$1
    local error_file
    local latest_url
    local curl_status
    local curl_error

    error_file=$(mktemp)
    set +e
    latest_url=$(curl -fsSLI \
        --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
        -H "User-Agent: aur-packages-ci" \
        -o /dev/null \
        -w '%{url_effective}' \
        "$url" 2>"$error_file")
    curl_status=$?
    set -e

    if [ "$curl_status" -ne 0 ]; then
        curl_error=$(<"$error_file")
        curl_error=${curl_error//$'\n'/ }
        rm -f "$error_file"
        die "Failed to resolve latest GitHub release URL (curl exit ${curl_status}${curl_error:+: ${curl_error}})"
    fi

    rm -f "$error_file"
    printf '%s' "$latest_url"
}

github_fetch_url_text() {
    local url=$1

    curl -fsSL \
        --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
        -H "User-Agent: aur-packages-ci" \
        "$url"
}

log_github_asset_match_failure() {
    local arch=$1
    local selector=$2
    local release_tag=$3
    shift 3
    local assets=("$@")
    local asset

    log_error "Failed to match GitHub release asset for ${arch}"
    log_error "Release tag: ${release_tag:-unknown}"
    log_error "Regex: ${selector}"

    if [ "${#assets[@]}" -eq 0 ]; then
        log_error "Available assets: <none>"
    else
        log_error "Available assets:"
        for asset in "${assets[@]}"; do
            log_error "  ${asset}"
        done
    fi

    exit 1
}

resolve_github_release_assets() {
    require_cmd curl
    require_cmd jq

    if [ -n "$UPSTREAM_RELEASE_TAG_PREFIX" ]; then
        resolve_github_release_family_assets
        return 0
    fi

    local api_url
    if [ "$UPSTREAM_ALLOW_PRERELEASE" = "true" ]; then
        api_url="https://api.github.com/repos/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases"
    else
        api_url="https://api.github.com/repos/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases/latest"
    fi

    local response_file
    response_file=$(mktemp)
    if ! github_api_request_to_file "$api_url" "$response_file"; then
        log_info "GitHub API unavailable (${GITHUB_API_FAILURE_REASON:-unknown reason}); falling back to release page scraping."
        rm -f "$response_file"
        resolve_github_release_assets_via_web
        return 0
    fi

    local response
    response=$(<"$response_file")
    rm -f "$response_file"

    local release_json=$response
    if [ "$UPSTREAM_ALLOW_PRERELEASE" = "true" ]; then
        release_json=$(printf '%s' "$response" | jq 'first')
    fi

    local latest_tag
    latest_tag=$(printf '%s' "$release_json" | jq -r '.tag_name // empty')
    [ -n "$latest_tag" ] || die "Could not extract tag_name from GitHub release metadata"
    GITHUB_RELEASE_TAG=$latest_tag

    RESOLVED_VERSION=$latest_tag
    if [ -n "$UPSTREAM_TAG_PREFIX" ] && [[ "$RESOLVED_VERSION" == "${UPSTREAM_TAG_PREFIX}"* ]]; then
        RESOLVED_VERSION=${RESOLVED_VERSION#"$UPSTREAM_TAG_PREFIX"}
    fi

    resolve_github_asset_for_arch x86_64 "$release_json"
    resolve_github_asset_for_arch aarch64 "$release_json"
}

resolve_github_release_family_assets() {
    local releases_json
    local release_tags=()
    local latest_tag
    local release_json
    local failed_tags=()

    releases_json=$(github_fetch_releases_json)
    mapfile -t release_tags < <(
        printf '%s' "$releases_json" \
            | jq -r --arg prefix "$UPSTREAM_RELEASE_TAG_PREFIX" '.[] | select((.tag_name // "") | startswith($prefix)) | .tag_name' \
            | sort -rV
    )

    [ "${#release_tags[@]}" -gt 0 ] || die "No GitHub releases found with tag prefix: ${UPSTREAM_RELEASE_TAG_PREFIX}"

    for latest_tag in "${release_tags[@]}"; do
        release_json=$(printf '%s' "$releases_json" | jq -c --arg tag "$latest_tag" 'first(.[] | select((.tag_name // "") == $tag))')
        [ -n "$release_json" ] && [ "$release_json" != null ] || continue

        GITHUB_RELEASE_TAG=$latest_tag
        RESOLVED_VERSION=${latest_tag#"$UPSTREAM_RELEASE_TAG_PREFIX"}
        [ -n "$RESOLVED_VERSION" ] || continue

        if try_resolve_github_assets_for_configured_arches "$release_json"; then
            return 0
        fi

        failed_tags+=("$latest_tag")
    done

    if [ "${#failed_tags[@]}" -gt 0 ]; then
        log_error "Checked release tags without finding all required assets:"
        printf '!! ERROR:   %s\n' "${failed_tags[@]}" >&2
    fi

    if [ "${BINARY_RELEASE_ENABLED:-false}" = true ]; then
        log_error "This package consumes a self-built binary release asset. Bootstrap or update it with:"
        log_error "  ./scripts/ci_manager.sh build-binary-release ${PKGNAME}"
    fi

    die "No GitHub release with required assets found for tag prefix: ${UPSTREAM_RELEASE_TAG_PREFIX}"
}

try_resolve_github_assets_for_configured_arches() {
    local release_json=$1
    local arch

    for arch in "${ARCHES[@]}"; do
        github_arch_has_asset_matcher "$arch" || die "Missing UPSTREAM_ASSET_NAME or ASSET_SELECTOR for architecture: ${arch}"
        try_resolve_github_asset_for_arch "$arch" "$release_json" || return 1
    done

    return 0
}

resolve_github_release_assets_via_web() {
    local latest_url
    latest_url=$(github_fetch_latest_release_url "https://github.com/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases/latest")

    local latest_tag=${latest_url##*/}
    [ -n "$latest_tag" ] || die "Could not determine latest GitHub release tag"
    GITHUB_RELEASE_TAG=$latest_tag

    RESOLVED_VERSION=$latest_tag
    if [ -n "$UPSTREAM_TAG_PREFIX" ] && [[ "$RESOLVED_VERSION" == "${UPSTREAM_TAG_PREFIX}"* ]]; then
        RESOLVED_VERSION=${RESOLVED_VERSION#"$UPSTREAM_TAG_PREFIX"}
    fi

    local assets_url="https://github.com/${UPSTREAM_REPO_USER}/${UPSTREAM_REPO_NAME}/releases/expanded_assets/${latest_tag}"
    local assets_html
    assets_html=$(github_fetch_url_text "$assets_url") || die "Failed to fetch GitHub expanded assets page: ${assets_url}"

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
    local match_description

    github_arch_has_asset_matcher "$arch" || return 0

    if try_resolve_github_asset_for_arch "$arch" "$release_json"; then
        return 0
    fi

    match_description=$(github_asset_match_description_for_arch "$arch")

    local asset_names=()
    mapfile -t asset_names < <(printf '%s' "$release_json" | jq -r '.assets[].name // empty')
    log_github_asset_match_failure "$arch" "$match_description" "$GITHUB_RELEASE_TAG" "${asset_names[@]}"
}

try_resolve_github_asset_for_arch() {
    local arch=$1
    local release_json=$2

    local suffix
    suffix=$(arch_var_suffix "$arch")
    local exact_name
    local selector

    exact_name=$(github_exact_asset_name_for_arch "$arch")
    selector=$(github_asset_selector_for_arch "$arch")
    [ -n "$exact_name" ] || [ -n "$selector" ] || return 0

    local download_url
    if [ -n "$exact_name" ]; then
        download_url=$(printf '%s' "$release_json" | jq -r --arg name "$exact_name" '
            .assets[]
            | select((.name // "") == $name)
            | .browser_download_url
            ' | head -n 1)
    else
        download_url=$(printf '%s' "$release_json" | jq -r --arg regex "$selector" '
            .assets[]
            | select((.name // "") | test($regex))
            | .browser_download_url
            ' | head -n 1)
    fi

    [ -n "$download_url" ] || return 1

    local resolved_var="RESOLVED_SOURCE_URL_${suffix}"
    printf -v "$resolved_var" '%s' "$download_url"
}

resolve_github_web_asset_for_arch() {
    local arch=$1

    local suffix
    suffix=$(arch_var_suffix "$arch")
    local exact_name
    local selector
    local match_description

    exact_name=$(github_exact_asset_name_for_arch "$arch")
    selector=$(github_asset_selector_for_arch "$arch")
    [ -n "$exact_name" ] || [ -n "$selector" ] || return 0

    local asset_url
    for asset_url in "${GITHUB_RELEASE_WEB_ASSET_URLS[@]}"; do
        local asset_name=${asset_url##*/}
        if { [ -n "$exact_name" ] && [ "$asset_name" = "$exact_name" ]; } || { [ -z "$exact_name" ] && [[ "$asset_name" =~ $selector ]]; }; then
            local resolved_var="RESOLVED_SOURCE_URL_${suffix}"
            printf -v "$resolved_var" '%s' "$asset_url"
            return 0
        fi
    done

    local asset_names=()
    local available_asset_url
    for available_asset_url in "${GITHUB_RELEASE_WEB_ASSET_URLS[@]}"; do
        asset_names+=("${available_asset_url##*/}")
    done

    match_description=$(github_asset_match_description_for_arch "$arch")
    log_github_asset_match_failure "$arch" "$match_description" "$GITHUB_RELEASE_TAG" "${asset_names[@]}"
}
