#!/bin/bash

render_deb_repack_pkgbuild() {
    local workspace=$1
    local service_path=""
    local source_name_x86_64

    register_workspace_sync_file "PKGBUILD"

    if [ "$SERVICE_MODE" != "none" ]; then
        service_path=$(service_install_path)
    fi

    source_name_x86_64=$(resolved_source_name_for_arch "x86_64")

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

_deb_source_file=$(printf '%q' "$source_name_x86_64")
_deb_relocate_usr_local=$(printf '%q' "$DEB_RELOCATE_USR_LOCAL")
_service_file=$(printf '%q' "$WORKSPACE_SERVICE_FILE_NAME")
_service_install_path=$(printf '%q' "$service_path")
$(render_array_assignment "_doc_files" "${DOC_FILES[@]}")
$(render_array_assignment "_license_files" "${LICENSE_FILES[@]}")
$(render_persisted_state_assignments)

prepare() {
    rm -rf "\${srcdir}/_deb_extract" "\${srcdir}/_deb_root"
    mkdir -p "\${srcdir}/_deb_extract" "\${srcdir}/_deb_root"

    bsdtar -xf "\${srcdir}/\${_deb_source_file}" -C "\${srcdir}/_deb_extract"

    local data_archives=("\${srcdir}/_deb_extract"/data.tar.*)
    [ -e "\${data_archives[0]}" ] || {
        echo "Missing data.tar.* inside Debian package" >&2
        return 1
    }

    bsdtar -xf "\${data_archives[0]}" -C "\${srcdir}/_deb_root"
}

package() {
    install -d "\${pkgdir}"
    cp -a "\${srcdir}/_deb_root/." "\${pkgdir}/"

    if [ "\${_deb_relocate_usr_local}" = true ] && [ -d "\${pkgdir}/usr/local" ]; then
        install -d "\${pkgdir}/usr"
        cp -a "\${pkgdir}/usr/local/." "\${pkgdir}/usr/"
        rm -rf "\${pkgdir}/usr/local"
    fi

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
}
