#!/bin/bash

PACKAGE_SPEC_SUPPORTED_VERSION=1
PACKAGE_SPEC_FILENAME=package.toml

PACKAGE_DEFINITION_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE_SPEC_TOML_PARSER="${PACKAGE_DEFINITION_LIB_DIR}/package_spec_toml.py"

package_spec_toml() {
    local command=$1
    local spec_path=$2

    command -v python3 >/dev/null 2>&1 || {
        printf 'Required command not found: python3\n' >&2
        return 1
    }
    python3 -c 'import tomllib' >/dev/null 2>&1 || {
        printf 'PackageSpec TOML parsing requires Python 3.11 or newer with tomllib\n' >&2
        return 1
    }

    python3 "$PACKAGE_SPEC_TOML_PARSER" "$command" "$spec_path"
}

package_definition_path() {
    local package_dir=$1
    local spec_candidate="${package_dir}/${PACKAGE_SPEC_FILENAME}"
    local legacy_candidate="${package_dir}/package.conf"

    if [ -f "$spec_candidate" ] && [ -f "$legacy_candidate" ]; then
        printf 'Package directory must not contain both %s and package.conf: %s\n' "$PACKAGE_SPEC_FILENAME" "$package_dir" >&2
        return 1
    fi

    if [ -f "$spec_candidate" ]; then
        printf '%s' "$spec_candidate"
        return 0
    fi

    return 1
}

package_has_definition() {
    package_definition_path "$1" >/dev/null 2>&1
}

discover_package_definition_files() {
    local package_root=${1:-packages}

    [ -d "$package_root" ] || return 0
    find "$package_root" -mindepth 2 -maxdepth 2 -name "$PACKAGE_SPEC_FILENAME" -type f | sort
}

validate_package_spec_data_only() {
    local spec_path=$1

    package_spec_toml validate "$spec_path"
}

package_spec_pkgname_from_file() {
    local spec_path=$1

    [ -f "$spec_path" ] || return 0
    package_spec_toml name "$spec_path"
}

package_spec_shell_assignments() {
    local spec_path=$1

    package_spec_toml shell "$spec_path"
}
