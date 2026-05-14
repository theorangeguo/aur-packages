#!/bin/bash

render_source_cargo_pkgbuild() {
    local workspace=$1
    local pkgname=$PKGNAME
    local pkgver=$TARGET_PKGVER
    local source_dir
    local binary_source_path=${BINARY_SOURCE_PATH:-target/release/$BINARY_NAME}
    local patch_file
    local patch_file_basenames=()

    source_dir=$(expand_template "$SOURCE_DIR")

    for patch_file in "${PATCH_FILES[@]}"; do
        [ -n "$patch_file" ] || continue
        patch_file_basenames+=("$(basename "$patch_file")")
    done

    register_workspace_sync_file "PKGBUILD"

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

_source_dir=$(printf '%q' "$source_dir")
_binary_source_path=$(printf '%q' "$binary_source_path")
_install_bin_path=$(printf '%q' "$INSTALL_BIN_PATH")
_run_check=$(printf '%q' "$RUN_CHECK")
$(render_array_assignment "_patch_files" "${patch_file_basenames[@]}")
$(render_array_assignment "_cargo_fetch_args" "${CARGO_FETCH_ARGS[@]}")
$(render_array_assignment "_cargo_build_args" "${CARGO_BUILD_ARGS[@]}")
$(render_array_assignment "_cargo_check_args" "${CARGO_CHECK_ARGS[@]}")
$(render_array_assignment "_doc_files" "${DOC_FILES[@]}")
$(render_array_assignment "_license_files" "${LICENSE_FILES[@]}")
$(render_persisted_state_assignments)

prepare() {
    cd "\${srcdir}/\${_source_dir}"

    local patch_file
    for patch_file in "\${_patch_files[@]}"; do
        patch -Np1 -i "\${srcdir}/\${patch_file}"
    done

    if [ "\${#_cargo_fetch_args[@]}" -gt 0 ]; then
        cargo fetch "\${_cargo_fetch_args[@]}"
    else
        local target
        target=\$(rustc -vV | sed -n 's/^host: //p')
        cargo fetch --locked --target "\${target}"
    fi
}

build() {
    cd "\${srcdir}/\${_source_dir}"

    if [ "\${#_cargo_build_args[@]}" -gt 0 ]; then
        cargo build "\${_cargo_build_args[@]}"
    else
        cargo build --release --frozen
    fi
}

check() {
    [ "\${_run_check}" = true ] || return 0

    cd "\${srcdir}/\${_source_dir}"
    if [ "\${#_cargo_check_args[@]}" -gt 0 ]; then
        cargo test "\${_cargo_check_args[@]}"
    else
        cargo test --frozen
    fi
}

package() {
    cd "\${srcdir}/\${_source_dir}"

    install -Dm755 "\${_binary_source_path}" "\${pkgdir}\${_install_bin_path}"

    local doc_file
    local doc_source
    for doc_file in "\${_doc_files[@]}"; do
        doc_source=""
        if [ -f "\${doc_file}" ]; then
            doc_source="\${doc_file}"
        elif [ -f "\${srcdir}/\${doc_file}" ]; then
            doc_source="\${srcdir}/\${doc_file}"
        else
            continue
        fi

        install -Dm644 "\${doc_source}" "\${pkgdir}/usr/share/doc/\${pkgname}/\$(basename "\${doc_file}")"
    done

    local license_file
    local license_source
    for license_file in "\${_license_files[@]}"; do
        license_source=""
        if [ -f "\${license_file}" ]; then
            license_source="\${license_file}"
        elif [ -f "\${srcdir}/\${license_file}" ]; then
            license_source="\${srcdir}/\${license_file}"
        else
            continue
        fi

        install -Dm644 "\${license_source}" "\${pkgdir}/usr/share/licenses/\${pkgname}/\$(basename "\${license_file}")"
    done
}
EOF
}
