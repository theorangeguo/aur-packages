#!/bin/bash

log_group_start() {
    echo "::group::$1"
}

log_group_end() {
    echo "::endgroup::"
}

log_info() {
    echo "==> $1"
}

log_error() {
    echo "!! ERROR: $1" >&2
}

die() {
    log_error "$1"
    exit 1
}

require_cmd() {
    local cmd=$1
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

expand_template() {
    local template=$1
    local result

    eval "result=\"$template\""
    printf '%s' "$result"
}

render_array_assignment() {
    local name=$1
    shift || true

    printf '%s=(' "$name"
    if [ "$#" -gt 0 ]; then
        local item
        for item in "$@"; do
            printf '%q ' "$item"
        done
    fi
    printf ')\n'
}

render_string_assignment() {
    local name=$1
    local value=$2

    printf '%s=%q\n' "$name" "$value"
}

ensure_unique_basename() {
    local destination=$1

    if [ -e "$destination" ]; then
        die "Refusing to overwrite existing generated asset: $(basename "$destination")"
    fi
}

copy_package_asset() {
    local package_dir=$1
    local relative_path=$2
    local workspace=$3
    local source_path="${package_dir}/${relative_path}"
    local destination_path="${workspace}/$(basename "$relative_path")"

    [ -f "$source_path" ] || die "Package asset not found: $relative_path"
    ensure_unique_basename "$destination_path"
    cp "$source_path" "$destination_path"
    printf '%s' "$destination_path"
}

service_install_path() {
    case "$SERVICE_SCOPE" in
        user)
            printf '/usr/lib/systemd/user/%s' "$SERVICE_NAME"
            ;;
        system)
            printf '/usr/lib/systemd/system/%s' "$SERVICE_NAME"
            ;;
        *)
            die "Unsupported SERVICE_SCOPE: $SERVICE_SCOPE"
            ;;
    esac
}

pkgbuild_var_from_file() {
    local file_path=$1
    local var_name=$2
    local line

    [ -f "$file_path" ] || return 0

    line=$(grep -E "^${var_name}=" "$file_path" | head -n 1 || true)
    [ -n "$line" ] || return 0

    if [[ "$line" == *\"* ]]; then
        printf '%s\n' "$line" | cut -d'"' -f2
    else
        printf '%s\n' "$line" | cut -d'=' -f2
    fi
}

arch_var_suffix() {
    case "$1" in
        x86_64) printf 'X86_64' ;;
        aarch64) printf 'AARCH64' ;;
        *) die "Unsupported architecture in template renderer: $1" ;;
    esac
}

resolved_source_url_for_arch() {
    local arch=$1
    local suffix
    suffix=$(arch_var_suffix "$arch")
    local var_name="RESOLVED_SOURCE_URL_${suffix}"

    printf '%s' "${!var_name}"
}

resolved_source_name_for_arch() {
    local arch=$1
    local suffix
    suffix=$(arch_var_suffix "$arch")
    local var_name="SOURCE_RENAME_${suffix}"
    local template=${!var_name}

    [ -n "$template" ] || die "Missing source rename template for architecture: $arch"

    local pkgname=$PKGNAME
    local pkgver=$TARGET_PKGVER
    local carch=$arch
    expand_template "$template"
}

reset_workspace_state() {
    WORKSPACE_COMMON_SOURCE_FILES=()
    WORKSPACE_SYNC_FILES=()
    WORKSPACE_INSTALL_FILE_NAME=""
    WORKSPACE_SERVICE_FILE_NAME=""
}

register_workspace_sync_file() {
    WORKSPACE_SYNC_FILES+=("$1")
}

register_common_source_file() {
    WORKSPACE_COMMON_SOURCE_FILES+=("$1")
    register_workspace_sync_file "$1"
}

render_common_source_arrays() {
    render_array_assignment "source" "${WORKSPACE_COMMON_SOURCE_FILES[@]}"

    local common_checksums=()
    local _item
    for _item in "${WORKSPACE_COMMON_SOURCE_FILES[@]}"; do
        common_checksums+=("SKIP")
    done
    render_array_assignment "sha256sums" "${common_checksums[@]}"

    local arch
    for arch in "${ARCHES[@]}"; do
        local resolved_url
        resolved_url=$(resolved_source_url_for_arch "$arch")
        [ -n "$resolved_url" ] || continue

        local source_name
        source_name=$(resolved_source_name_for_arch "$arch")
        render_array_assignment "source_${arch}" "${source_name}::${resolved_url}"
        render_array_assignment "sha256sums_${arch}" "SKIP"
    done
}
