#!/bin/bash

resolve_custom_upstream_state() {
    declare -F resolve_upstream_state >/dev/null 2>&1 || die "UPSTREAM_TYPE=custom-hook requires hooks.sh with resolve_upstream_state()"
    local package_state_before
    local package_state_after

    RESOLVED_VERSION=""
    package_state_before=$(package_spec_definition_state_digest)
    resolve_upstream_state
    package_state_after=$(package_spec_definition_state_digest)

    [ "$package_state_before" = "$package_state_after" ] \
        || die "resolve_upstream_state() must not mutate PackageSpec fields; use RESOLVED_* or STATE_* outputs"

    [ -n "$RESOLVED_VERSION" ] || die "resolve_upstream_state() must set RESOLVED_VERSION"
}
