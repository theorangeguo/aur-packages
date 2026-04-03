#!/bin/bash

resolve_custom_upstream_state() {
    declare -F resolve_upstream_state >/dev/null 2>&1 || die "UPSTREAM_TYPE=custom-hook requires hooks.sh with resolve_upstream_state()"

    RESOLVED_VERSION=""
    resolve_upstream_state

    [ -n "$RESOLVED_VERSION" ] || die "resolve_upstream_state() must set RESOLVED_VERSION"
}
