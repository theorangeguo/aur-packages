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

PACKAGE_ROOT_DIR=${PACKAGE_ROOT_DIR:-packages}

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

resolve_package_dir_input() {
    local input=$1
    local candidate

    [ -n "$input" ] || die "Package directory is required"
    input=${input#./}

    case "$input" in
        packages/*)
            [[ "$input" =~ ^packages/[a-zA-Z0-9._-]+$ ]] || die "Invalid package directory: $input"
            candidate=$input
            ;;
        *)
            [[ "$input" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Invalid package directory: $input"
            candidate="${PACKAGE_ROOT_DIR}/${input}"
            ;;
    esac

    [ -d "$candidate" ] || die "Directory '$candidate' does not exist."
    [ -f "$candidate/package.conf" ] || die "package.conf not found in '$candidate'."

    printf '%s' "$candidate"
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

render_pkgbuild_header() {
    cat <<EOF
# Maintainer: orange-guo
# Packaging Repo: ${PACKAGING_REPO_URL}

EOF
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

resolved_common_source_url() {
    printf '%s' "${RESOLVED_SOURCE_URL}"
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

resolved_common_source_name() {
    local template=$SOURCE_RENAME

    [ -n "$template" ] || die "Missing common source rename template"

    local pkgname=$PKGNAME
    local pkgver=$TARGET_PKGVER
    expand_template "$template"
}

is_http_source_url() {
    case "$1" in
        http://*|https://*) return 0 ;;
        *) return 1 ;;
    esac
}

fetch_url_text_with_retry() {
    local url=$1

    [ -n "$url" ] || die "URL is required"
    require_cmd curl

    curl -fsSL --retry 20 --retry-all-errors --retry-delay 2 --connect-timeout 20 "$url"
}

prefetch_remote_source() {
    local url=$1
    local target_path=$2
    local partial_path="${target_path}.part"

    [ -n "$SRCDEST" ] || die "SRCDEST must be set before prefetching sources"
    [ -n "$url" ] || return 0
    [ -n "$target_path" ] || die "Target path is required for source prefetch"

    is_http_source_url "$url" || return 0
    require_cmd curl

    mkdir -p "$SRCDEST"

    if [ -s "$target_path" ]; then
        log_info "Using cached source: $(basename "$target_path")"
        return 0
    fi

    [ -e "$target_path" ] && rm -f "$target_path"
    [ -e "$partial_path" ] && [ ! -s "$partial_path" ] && rm -f "$partial_path"

    log_info "Prefetching source: $(basename "$target_path")"
    if ! curl -fsSL --retry 20 --retry-all-errors --retry-delay 2 -C - -o "$partial_path" "$url"; then
        log_info "Resume attempt failed for $(basename "$target_path"); retrying from scratch."
        rm -f "$partial_path"
        curl -fsSL --retry 20 --retry-all-errors --retry-delay 2 -o "$partial_path" "$url" \
            || die "Failed to prefetch source: $url"
    fi

    [ -s "$partial_path" ] || die "Prefetched source is empty: $(basename "$target_path")"
    mv "$partial_path" "$target_path"
}

prefetch_resolved_sources() {
    local common_source_url
    local common_source_name
    local arch
    local resolved_url
    local source_name

    [ -n "$SRCDEST" ] || die "SRCDEST must be set before prefetching sources"

    common_source_url=$(resolved_common_source_url)
    if [ -n "$common_source_url" ]; then
        common_source_name=$(resolved_common_source_name)
        prefetch_remote_source "$common_source_url" "$SRCDEST/$common_source_name"
    fi

    for arch in "${ARCHES[@]}"; do
        resolved_url=$(resolved_source_url_for_arch "$arch")
        [ -n "$resolved_url" ] || continue

        source_name=$(resolved_source_name_for_arch "$arch")
        prefetch_remote_source "$resolved_url" "$SRCDEST/$source_name"
    done
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
    local common_sources=("${WORKSPACE_COMMON_SOURCE_FILES[@]}")
    local common_source_url
    common_source_url=$(resolved_common_source_url)

    if [ -n "$common_source_url" ]; then
        local common_source_name
        common_source_name=$(resolved_common_source_name)
        common_sources+=("${common_source_name}::${common_source_url}")
    fi

    render_array_assignment "source" "${common_sources[@]}"

    local common_checksums=()
    local _item
    for _item in "${common_sources[@]}"; do
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

render_persisted_state_assignments() {
    local state_key
    for state_key in "${PERSIST_STATE_KEYS[@]}"; do
        [ -n "$state_key" ] || continue

        local state_var="STATE_${state_key}"
        local state_value=${!state_var}
        [ -n "$state_value" ] || die "Missing persisted state value for ${state_var}"

        local pkgbuild_var="_${state_key,,}"
        render_string_assignment "$pkgbuild_var" "$state_value"
    done
}

ensure_valid_pgp_keys() {
    [ "${#VALIDPGPKEYS[@]}" -gt 0 ] || return 0

    require_cmd gpg

    local key
    local keyserver
    for key in "${VALIDPGPKEYS[@]}"; do
        [ -n "$key" ] || continue

        if gpg --list-keys "$key" >/dev/null 2>&1; then
            continue
        fi

        log_info "Importing PGP key: $key"
        for keyserver in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org; do
            if gpg --batch --keyserver "$keyserver" --recv-keys "$key" >/dev/null 2>&1; then
                break
            fi
        done

        gpg --list-keys "$key" >/dev/null 2>&1 || die "Failed to import required PGP key: $key"
    done
}
