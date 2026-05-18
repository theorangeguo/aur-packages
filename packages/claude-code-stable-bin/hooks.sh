#!/bin/bash

resolve_upstream_state() {
    local bucket_url="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
    local channel="stable"

    RESOLVED_VERSION=$(fetch_url_text_with_retry "${bucket_url}/${channel}") || die "Failed to fetch Claude Code ${channel} version"
    RESOLVED_VERSION=$(printf '%s' "$RESOLVED_VERSION" | tr -d '\r\n')
    [[ "$RESOLVED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?$ ]] || die "Invalid Claude Code version: ${RESOLVED_VERSION}"

    RESOLVED_SOURCE_URL_X86_64="${bucket_url}/${RESOLVED_VERSION}/linux-x64/claude"
    RESOLVED_SOURCE_URL="https://raw.githubusercontent.com/anthropics/claude-code/v${RESOLVED_VERSION}/LICENSE.md"
}
