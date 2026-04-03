#!/bin/bash

render_binary_archive_pkgbuild() {
    local workspace=$1
    local binary_source_path=${BINARY_SOURCE_PATH:-$BINARY_NAME}
    local service_path=""

    register_workspace_sync_file "PKGBUILD"

    if [ "$SERVICE_MODE" != "none" ]; then
        service_path=$(service_install_path)
    fi

    cat > "${workspace}/PKGBUILD" <<EOF
# Maintainer: orange-guo
# Packaging Repo: https://github.com/orange-guo/aur-packages

$(render_string_assignment "pkgname" "$PKGNAME")
$(render_string_assignment "pkgver" "$TARGET_PKGVER")
$(render_string_assignment "pkgrel" "$TARGET_PKGREL")
$(render_string_assignment "pkgdesc" "$PKGDESC")
$(render_array_assignment "arch" "${ARCHES[@]}")
$(render_string_assignment "url" "$URL")
$(render_array_assignment "license" "${LICENSES[@]}")
$(render_array_assignment "depends" "${DEPENDS[@]}")
$(render_array_assignment "makedepends" "${MAKEDEPENDS[@]}")
$(render_array_assignment "options" "${OPTIONS[@]}")
$(render_array_assignment "provides" "${PROVIDES[@]}")
$(render_array_assignment "conflicts" "${CONFLICTS[@]}")
$( [ -n "$WORKSPACE_INSTALL_FILE_NAME" ] && render_string_assignment "install" "$WORKSPACE_INSTALL_FILE_NAME" )
$(render_common_source_arrays)

_binary_source_path=$(printf '%q' "$binary_source_path")
_install_bin_path=$(printf '%q' "$INSTALL_BIN_PATH")
_service_file=$(printf '%q' "$WORKSPACE_SERVICE_FILE_NAME")
_service_install_path=$(printf '%q' "$service_path")
$(render_array_assignment "_doc_files" "${DOC_FILES[@]}")
$(render_array_assignment "_license_files" "${LICENSE_FILES[@]}")

package() {
    install -Dm755 "\${srcdir}/\${_binary_source_path}" "\${pkgdir}\${_install_bin_path}"

    local doc_file
    for doc_file in "\${_doc_files[@]}"; do
        [ -f "\${srcdir}/\${doc_file}" ] || continue
        install -Dm644 "\${srcdir}/\${doc_file}" "\${pkgdir}/usr/share/doc/\${pkgname}/\$(basename "\${doc_file}")"
    done

    local license_file
    for license_file in "\${_license_files[@]}"; do
        [ -f "\${srcdir}/\${license_file}" ] || continue
        install -Dm644 "\${srcdir}/\${license_file}" "\${pkgdir}/usr/share/licenses/\${pkgname}/\$(basename "\${license_file}")"
    done

    if [ -n "\${_service_file}" ] && [ -f "\${srcdir}/\${_service_file}" ]; then
        install -Dm644 "\${srcdir}/\${_service_file}" "\${pkgdir}\${_service_install_path}"
    fi
}
EOF

    if declare -F render_package_append >/dev/null 2>&1; then
        render_package_append >> "${workspace}/PKGBUILD"
    fi
}
