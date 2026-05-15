#!/bin/bash

binary_release_repo() {
    printf '%s' "${BINARY_RELEASE_REPO:-${GITHUB_REPOSITORY:-orange-guo/aur-packages}}"
}

binary_release_detect_container_runtime() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        printf 'docker'
        return 0
    fi

    if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        printf 'podman'
        return 0
    fi

    return 1
}

binary_release_normalize_requested_version() {
    local requested=$1
    local version=${requested#v}

    if [ -n "$BINARY_RELEASE_UPSTREAM_TAG_PREFIX" ] && [[ "$version" == "${BINARY_RELEASE_UPSTREAM_TAG_PREFIX}"* ]]; then
        version=${version#"$BINARY_RELEASE_UPSTREAM_TAG_PREFIX"}
    fi

    printf '%s' "$version"
}

binary_release_resolve_upstream_version() {
    local requested_version=$1
    local response_file
    local latest_tag
    local version

    if [ -n "$requested_version" ]; then
        binary_release_normalize_requested_version "$requested_version"
        return 0
    fi

    case "$BINARY_RELEASE_UPSTREAM_TYPE" in
        github-source-archive)
            require_cmd curl
            require_cmd jq
            response_file=$(mktemp)
            github_api_request_to_file \
                "https://api.github.com/repos/${BINARY_RELEASE_UPSTREAM_REPO_USER}/${BINARY_RELEASE_UPSTREAM_REPO_NAME}/releases/latest" \
                "$response_file" \
                || die "Failed to resolve latest upstream release for ${BINARY_RELEASE_UPSTREAM_REPO_USER}/${BINARY_RELEASE_UPSTREAM_REPO_NAME}: ${GITHUB_API_FAILURE_REASON:-unknown reason}"
            latest_tag=$(jq -r '.tag_name // empty' "$response_file")
            rm -f "$response_file"
            [ -n "$latest_tag" ] || die "Could not extract upstream release tag for ${PKGNAME}"
            version=$(binary_release_normalize_requested_version "$latest_tag")
            [ -n "$version" ] || die "Could not normalize upstream release tag for ${PKGNAME}: ${latest_tag}"
            printf '%s' "$version"
            ;;
        *)
            die "Unsupported BINARY_RELEASE_UPSTREAM_TYPE: $BINARY_RELEASE_UPSTREAM_TYPE"
            ;;
    esac
}

binary_release_pkgver() {
    local upstream_version=$1
    local release_rev=$BINARY_RELEASE_REV
    local pkgver

    pkgver=$(expand_template "$BINARY_RELEASE_VERSION_TEMPLATE")
    [ -n "$pkgver" ] || die "Computed empty binary release pkgver for ${PKGNAME}"

    if [[ ! "$pkgver" =~ ^[A-Za-z0-9._+]+$ ]]; then
        die "Binary release pkgver contains unsupported characters: ${pkgver}"
    fi

    printf '%s' "$pkgver"
}

binary_release_tag() {
    local pkgver=$1
    printf '%s%s' "$BINARY_RELEASE_TAG_PREFIX" "$pkgver"
}

binary_release_asset_name_for_arch() {
    local arch=$1
    local pkgver=$2
    local suffix
    suffix=$(arch_var_suffix "$arch")
    local asset_var="BINARY_RELEASE_ASSET_${suffix}"
    local template=${!asset_var}

    [ -n "$template" ] || die "${asset_var} is required"

    local pkgname=$PKGNAME
    local carch=$arch
    expand_template "$template"
}

binary_release_source_archive_url() {
    local upstream_version=$1
    local upstream_tag="${BINARY_RELEASE_UPSTREAM_TAG_PREFIX}${upstream_version}"

    case "$BINARY_RELEASE_UPSTREAM_TYPE" in
        github-source-archive)
            printf 'https://github.com/%s/%s/archive/refs/tags/%s.tar.gz' \
                "$BINARY_RELEASE_UPSTREAM_REPO_USER" \
                "$BINARY_RELEASE_UPSTREAM_REPO_NAME" \
                "$upstream_tag"
            ;;
        *)
            die "Unsupported BINARY_RELEASE_UPSTREAM_TYPE: $BINARY_RELEASE_UPSTREAM_TYPE"
            ;;
    esac
}

binary_release_source_dir() {
    local upstream_version=$1
    local pkgver=$2
    local release_rev=$BINARY_RELEASE_REV
    local template=${BINARY_RELEASE_SOURCE_DIR:-${BINARY_RELEASE_UPSTREAM_REPO_NAME}-${upstream_version}}

    expand_template "$template"
}

binary_release_asset_exists() {
    local tag=$1
    local asset_name=$2
    local repo
    local asset_names
    local required_asset

    require_cmd gh
    repo=$(binary_release_repo)
    asset_names=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' 2>/dev/null || true)
    [ -n "$asset_names" ] || return 1

    for required_asset in "$asset_name" "${asset_name}.sha256sum" "${asset_name}.buildinfo"; do
        printf '%s\n' "$asset_names" | grep -Fx "$required_asset" >/dev/null 2>&1 || return 1
    done
}

write_binary_release_buildinfo() {
    local output_path=$1
    local arch=$2
    local upstream_version=$3
    local pkgver=$4
    local tag=$5
    local asset_name=$6
    local git_sha=${GITHUB_SHA:-}

    if [ -z "$git_sha" ] && command -v git >/dev/null 2>&1; then
        git_sha=$(git rev-parse HEAD 2>/dev/null || true)
    fi

    cat > "$output_path" <<EOF
package=${PKGNAME}
arch=${arch}
pkgver=${pkgver}
upstream_version=${upstream_version}
release_rev=${BINARY_RELEASE_REV}
release_tag=${tag}
asset_name=${asset_name}
build_template=${BINARY_RELEASE_TEMPLATE}
git_sha=${git_sha:-unknown}
EOF
}

publish_binary_release_asset() {
    local tag=$1
    local pkgver=$2
    local asset_path=$3
    local asset_name
    local repo
    local target

    require_cmd gh

    asset_name=$(basename "$asset_path")
    repo=$(binary_release_repo)
    target=${GITHUB_SHA:-}
    if [ -z "$target" ] && command -v git >/dev/null 2>&1; then
        target=$(git rev-parse HEAD 2>/dev/null || true)
    fi

    if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
        gh release upload "$tag" \
            "$asset_path" \
            "${asset_path}.sha256sum" \
            "${asset_path}.buildinfo" \
            --clobber \
            --repo "$repo"
    else
        gh release create "$tag" \
            "$asset_path" \
            "${asset_path}.sha256sum" \
            "${asset_path}.buildinfo" \
            --repo "$repo" \
            --target "$target" \
            --title "${PKGNAME} v${pkgver}" \
            --notes "Self-built binary release for ${PKGNAME} ${pkgver}."
    fi
}
