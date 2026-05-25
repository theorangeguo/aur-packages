#!/bin/bash

boxd_manifest_value() {
    local manifest=$1
    local key=$2

    printf '%s\n' "$manifest" \
        | sed -nE 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        | head -n 1
}

resolve_boxd_platform_manifest() {
    local platform=$1
    local manifest_url="https://boxd.sh/downloads/cli/latest-${platform}.json"
    local manifest
    local version
    local url
    local sha256

    manifest=$(fetch_url_text_with_retry "$manifest_url") || die "Failed to fetch boxd CLI manifest: ${manifest_url}"
    version=$(boxd_manifest_value "$manifest" "version")
    url=$(boxd_manifest_value "$manifest" "url")
    sha256=$(boxd_manifest_value "$manifest" "sha256")

    [ -n "$version" ] || die "boxd CLI manifest ${manifest_url} does not contain version"
    [ -n "$url" ] || die "boxd CLI manifest ${manifest_url} does not contain url"
    [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || die "boxd CLI manifest ${manifest_url} has invalid sha256"

    printf '%s\t%s\n' "$version" "$url"
}

resolve_upstream_state() {
    local x86_64_state
    local aarch64_state
    local version_x86_64
    local version_aarch64

    x86_64_state=$(resolve_boxd_platform_manifest "linux-amd64")
    aarch64_state=$(resolve_boxd_platform_manifest "linux-arm64")

    version_x86_64=${x86_64_state%%$'\t'*}
    RESOLVED_SOURCE_URL_X86_64=${x86_64_state#*$'\t'}

    version_aarch64=${aarch64_state%%$'\t'*}
    RESOLVED_SOURCE_URL_AARCH64=${aarch64_state#*$'\t'}

    [ "$version_x86_64" = "$version_aarch64" ] || die "boxd CLI manifests disagree on version: ${version_x86_64} vs ${version_aarch64}"
    [[ "$version_x86_64" =~ ^[0-9]+(\.[0-9]+)*([._][A-Za-z0-9]+)*$ ]] || die "Invalid boxd CLI version: ${version_x86_64}"

    case "$RESOLVED_SOURCE_URL_X86_64" in
        https://boxd.sh/downloads/cli/boxd-linux-amd64) ;;
        *) die "Unexpected boxd CLI x86_64 binary URL: ${RESOLVED_SOURCE_URL_X86_64}" ;;
    esac

    case "$RESOLVED_SOURCE_URL_AARCH64" in
        https://boxd.sh/downloads/cli/boxd-linux-arm64) ;;
        *) die "Unexpected boxd CLI aarch64 binary URL: ${RESOLVED_SOURCE_URL_AARCH64}" ;;
    esac

    RESOLVED_VERSION=$version_x86_64
}
