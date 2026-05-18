#!/bin/bash

render_binary_archive_pkgbuild() {
    local workspace=$1
    local pkgname=$PKGNAME
    local pkgver=$TARGET_PKGVER
    local carch=${CARCH:-}
    local binary_source_path
    local wrapper_source_path=${WRAPPER_SOURCE_PATH:-}
    local wrapper_install_path=${WRAPPER_INSTALL_PATH:-}
    local wrapper_mode=${WRAPPER_MODE:-755}
    local service_path=""

    register_workspace_sync_file "PKGBUILD"

    binary_source_path=$(expand_template "${BINARY_SOURCE_PATH:-$BINARY_NAME}")

    if [ "$SERVICE_MODE" != "none" ]; then
        service_path=$(service_install_path)
    fi

    cat > "${workspace}/PKGBUILD" <<EOF
$(render_pkgbuild_header)
$(render_string_assignment "pkgname" "$PKGNAME")
$(render_string_assignment "pkgver" "$TARGET_PKGVER")
$(render_string_assignment "pkgrel" "$TARGET_PKGREL")
$(render_string_assignment "pkgdesc" "$PKGDESC")
$(render_array_assignment "arch" "${ARCHES[@]}")
$(render_string_assignment "url" "$URL")
$(render_array_assignment "license" "${LICENSES[@]}")
$(render_array_assignment "depends" "${DEPENDS[@]}")
$(render_array_assignment "makedepends" "${MAKEDEPENDS[@]}")
$(render_array_assignment "checkdepends" "${CHECKDEPENDS[@]}")
$(render_array_assignment "optdepends" "${OPTDEPENDS[@]}")
$(render_array_assignment "options" "${OPTIONS[@]}")
$(render_array_assignment "provides" "${PROVIDES[@]}")
$(render_array_assignment "conflicts" "${CONFLICTS[@]}")
$(render_array_assignment "validpgpkeys" "${VALIDPGPKEYS[@]}")
$( [ -n "$WORKSPACE_INSTALL_FILE_NAME" ] && render_string_assignment "install" "$WORKSPACE_INSTALL_FILE_NAME" )
$(render_common_source_arrays)

_binary_source_path=$(printf '%q' "$binary_source_path")
_install_bin_path=$(printf '%q' "$INSTALL_BIN_PATH")
_wrapper_source_path=$(printf '%q' "$wrapper_source_path")
_wrapper_install_path=$(printf '%q' "$wrapper_install_path")
_wrapper_mode=$(printf '%q' "$wrapper_mode")
_service_file=$(printf '%q' "$WORKSPACE_SERVICE_FILE_NAME")
_service_install_path=$(printf '%q' "$service_path")
$(render_array_assignment "_doc_files" "${DOC_FILES[@]}")
$(render_array_assignment "_license_files" "${LICENSE_FILES[@]}")
$(render_persisted_state_assignments)

package() {
    _resolve_required_source_file() {
        local pattern=\$1
        local matches=()
        local nullglob_was_set=false

        shopt -q nullglob && nullglob_was_set=true
        shopt -s nullglob
        matches=("\${srcdir}"/\$pattern)
        [ "\$nullglob_was_set" = true ] || shopt -u nullglob

        if [ "\${#matches[@]}" -ne 1 ]; then
            printf 'Expected exactly one source match for pattern %s, found %s\n' "\$pattern" "\${#matches[@]}" >&2
            return 1
        fi

        [ -f "\${matches[0]}" ] || {
            printf 'Matched source is not a file: %s\n' "\${matches[0]}" >&2
            return 1
        }

        printf '%s\n' "\${matches[0]}"
    }

    _install_optional_source_files() {
        local pattern=\$1
        local target_dir=\$2
        local mode=\$3
        local matches=()
        local matched_file
        local nullglob_was_set=false

        shopt -q nullglob && nullglob_was_set=true
        shopt -s nullglob
        matches=("\${srcdir}"/\$pattern)
        [ "\$nullglob_was_set" = true ] || shopt -u nullglob

        for matched_file in "\${matches[@]}"; do
            [ -f "\$matched_file" ] || continue
            install -Dm"\$mode" "\$matched_file" "\${pkgdir}\${target_dir}/\$(basename "\$matched_file")"
        done
    }

    local binary_source_file
    binary_source_file=\$(_resolve_required_source_file "\${_binary_source_path}")
    install -Dm755 "\$binary_source_file" "\${pkgdir}\${_install_bin_path}"

    if [ -n "\${_wrapper_source_path}" ] && [ -n "\${_wrapper_install_path}" ]; then
        local wrapper_source_file
        wrapper_source_file=\$(_resolve_required_source_file "\${_wrapper_source_path}")
        install -Dm\${_wrapper_mode} "\$wrapper_source_file" "\${pkgdir}\${_wrapper_install_path}"
    fi

    local doc_file
    for doc_file in "\${_doc_files[@]}"; do
        _install_optional_source_files "\$doc_file" "/usr/share/doc/\${pkgname}" 644
    done

    local license_file
    for license_file in "\${_license_files[@]}"; do
        _install_optional_source_files "\$license_file" "/usr/share/licenses/\${pkgname}" 644
    done

    if [ -n "\${_service_file}" ] && [ -f "\${srcdir}/\${_service_file}" ]; then
        install -Dm644 "\${srcdir}/\${_service_file}" "\${pkgdir}\${_service_install_path}"
    fi
}
EOF
}
