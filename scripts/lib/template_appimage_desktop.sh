#!/bin/bash

render_appimage_desktop_pkgbuild() {
    local workspace=$1
    local service_path=""
    local source_name_x86_64
    local appimage_install_dir=${APPIMAGE_INSTALL_DIR:-$BINARY_NAME}
    local install_bin_dir

    register_workspace_sync_file "PKGBUILD"

    if [ "$SERVICE_MODE" != "none" ]; then
        service_path=$(service_install_path)
    fi

    source_name_x86_64=$(resolved_source_name_for_arch "x86_64")
    install_bin_dir=$(dirname "$INSTALL_BIN_PATH")

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

_appimage_source_file=$(printf '%q' "$source_name_x86_64")
_appimage_appdir_name=$(printf '%q' "$APPIMAGE_APPDIR_NAME")
_appimage_install_dir=$(printf '%q' "$appimage_install_dir")
_install_bin_path=$(printf '%q' "$INSTALL_BIN_PATH")
_install_bin_dir=$(printf '%q' "$install_bin_dir")
_desktop_exec_rewrite=$(printf '%q' "$DESKTOP_EXEC_REWRITE")
_desktop_name_rewrite=$(printf '%q' "$DESKTOP_NAME_REWRITE")
_service_file=$(printf '%q' "$WORKSPACE_SERVICE_FILE_NAME")
_service_install_path=$(printf '%q' "$service_path")
$(render_array_assignment "_desktop_candidates" "${DESKTOP_CANDIDATES[@]}")
$(render_array_assignment "_icon_candidates" "${ICON_CANDIDATES[@]}")
$(render_array_assignment "_license_files" "${LICENSE_FILES[@]}")
$(render_persisted_state_assignments)

prepare() {
    rm -rf "\${srcdir}/\${_appimage_appdir_name}"
    chmod +x "\${srcdir}/\${_appimage_source_file}"
    "\${srcdir}/\${_appimage_source_file}" --appimage-extract >/dev/null
}

package() {
    install -d "\${pkgdir}/opt/\${_appimage_install_dir}"
    cp -r "\${srcdir}/\${_appimage_appdir_name}/." "\${pkgdir}/opt/\${_appimage_install_dir}/"
    chmod -R a+rX "\${pkgdir}/opt/\${_appimage_install_dir}"

    install -d "\${pkgdir}\${_install_bin_dir}"
    ln -sf "/opt/\${_appimage_install_dir}/AppRun" "\${pkgdir}\${_install_bin_path}"

    local desktop_candidate=""
    local candidate
    for candidate in "\${_desktop_candidates[@]}"; do
        if [ -f "\${srcdir}/\${_appimage_appdir_name}/\${candidate}" ]; then
            desktop_candidate="\${candidate}"
            break
        fi
    done

    if [ -n "\${desktop_candidate}" ]; then
        install -Dm644 "\${srcdir}/\${_appimage_appdir_name}/\${desktop_candidate}" "\${pkgdir}/usr/share/applications/${BINARY_NAME}.desktop"
        if [ -n "\${_desktop_exec_rewrite}" ]; then
            sed -i "s|^Exec=.*|Exec=\${_desktop_exec_rewrite}|" "\${pkgdir}/usr/share/applications/${BINARY_NAME}.desktop"
        fi
        if [ -n "\${_desktop_name_rewrite}" ]; then
            sed -i "s|^Name=.*|Name=\${_desktop_name_rewrite}|" "\${pkgdir}/usr/share/applications/${BINARY_NAME}.desktop"
        fi
    fi

    local icon_candidate=""
    for candidate in "\${_icon_candidates[@]}"; do
        if [ -f "\${srcdir}/\${_appimage_appdir_name}/\${candidate}" ]; then
            icon_candidate="\${candidate}"
            break
        fi
    done

    if [ -n "\${icon_candidate}" ]; then
        install -Dm644 "\${srcdir}/\${_appimage_appdir_name}/\${icon_candidate}" "\${pkgdir}/usr/share/pixmaps/${BINARY_NAME}.png"
        if [ -f "\${pkgdir}/usr/share/applications/${BINARY_NAME}.desktop" ]; then
            sed -i "s|^Icon=.*|Icon=${BINARY_NAME}|" "\${pkgdir}/usr/share/applications/${BINARY_NAME}.desktop"
        fi
    fi

    local license_file
    for license_file in "\${_license_files[@]}"; do
        [ -f "\${srcdir}/\${license_file}" ] || [ -f "\${srcdir}/\${_appimage_appdir_name}/\${license_file}" ] || continue
        if [ -f "\${srcdir}/\${license_file}" ]; then
            install -Dm644 "\${srcdir}/\${license_file}" "\${pkgdir}/usr/share/licenses/\${pkgname}/\$(basename "\${license_file}")"
        else
            install -Dm644 "\${srcdir}/\${_appimage_appdir_name}/\${license_file}" "\${pkgdir}/usr/share/licenses/\${pkgname}/\$(basename "\${license_file}")"
        fi
    done

    if [ -n "\${_service_file}" ] && [ -f "\${srcdir}/\${_service_file}" ]; then
        install -Dm644 "\${srcdir}/\${_service_file}" "\${pkgdir}\${_service_install_path}"
    fi
}
EOF
}
