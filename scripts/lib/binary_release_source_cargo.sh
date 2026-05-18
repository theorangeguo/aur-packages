#!/bin/bash

build_binary_release_source_cargo() {
    local arch=$1
    local upstream_version=$2
    local pkgver=$3
    local asset_path=$4
    local runtime
    local tmp_root
    local output_dir
    local container_script
    local builder_script
    local source_url
    local source_dir
    local package_rel_dir
    local archive_destinations=()
    local archive_file

    [ "$arch" = x86_64 ] || die "source-cargo binary release currently supports x86_64 only: ${arch}"

    runtime=$(binary_release_detect_container_runtime) || die "docker or podman is required to build binary release artifacts"
    tmp_root=$(mktemp -d)
    output_dir="${tmp_root}/output"
    container_script="${tmp_root}/container.sh"
    builder_script="${tmp_root}/builder.sh"
    mkdir -p "$output_dir" "$(dirname "$asset_path")"

    source_url=$(binary_release_source_archive_url "$upstream_version")
    source_dir=$(binary_release_source_dir "$upstream_version" "$pkgver")
    package_rel_dir=${PACKAGE_DIR#"$REPO_ROOT"/}

    cat > "$container_script" <<EOF
#!/bin/bash
set -e
$(render_array_assignment "BINARY_RELEASE_MAKEDEPENDS" "${BINARY_RELEASE_MAKEDEPENDS[@]}")

pacman -Syu --noconfirm --needed "\${BINARY_RELEASE_MAKEDEPENDS[@]}"

if ! id -u builder >/dev/null 2>&1; then
    useradd -m builder
fi

mkdir -p /build /output
chown -R builder:builder /build /output
runuser -u builder -- env HOME=/home/builder /bin/bash /builder.sh
chown -R "\${HOST_UID}:\${HOST_GID}" /output
EOF

    cat > "$builder_script" <<EOF
#!/bin/bash
set -e
source_url=$(printf '%q' "$source_url")
source_dir=$(printf '%q' "$source_dir")
package_rel_dir=$(printf '%q' "$package_rel_dir")
$(render_array_assignment "BINARY_RELEASE_PATCH_FILES" "${BINARY_RELEASE_PATCH_FILES[@]}")
$(render_array_assignment "BINARY_RELEASE_CARGO_FETCH_ARGS" "${BINARY_RELEASE_CARGO_FETCH_ARGS[@]}")
$(render_array_assignment "BINARY_RELEASE_CARGO_BUILD_ARGS" "${BINARY_RELEASE_CARGO_BUILD_ARGS[@]}")
$(render_array_assignment "BINARY_RELEASE_CARGO_CHECK_ARGS" "${BINARY_RELEASE_CARGO_CHECK_ARGS[@]}")
$(render_array_assignment "BINARY_RELEASE_ARCHIVE_FILES" "${BINARY_RELEASE_ARCHIVE_FILES[@]}")
run_check=$(printf '%q' "$BINARY_RELEASE_RUN_CHECK")

cd /build
curl -fsSL \
    --retry 8 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
    -o source.tar.gz \
    "\$source_url"

tar -xzf source.tar.gz
cd "\$source_dir"

for patch_file in "\${BINARY_RELEASE_PATCH_FILES[@]}"; do
    [ -n "\$patch_file" ] || continue
    patch -Np1 -i "/work/\${package_rel_dir}/\${patch_file}"
done

if [ "\${#BINARY_RELEASE_CARGO_FETCH_ARGS[@]}" -gt 0 ]; then
    cargo fetch "\${BINARY_RELEASE_CARGO_FETCH_ARGS[@]}"
else
    target=\$(rustc -vV | sed -n 's/^host: //p')
    cargo fetch --locked --target "\$target"
fi

if [ "\${#BINARY_RELEASE_CARGO_BUILD_ARGS[@]}" -gt 0 ]; then
    cargo build "\${BINARY_RELEASE_CARGO_BUILD_ARGS[@]}"
else
    cargo build --release --frozen
fi

if [ "\$run_check" = true ]; then
    if [ "\${#BINARY_RELEASE_CARGO_CHECK_ARGS[@]}" -gt 0 ]; then
        cargo test "\${BINARY_RELEASE_CARGO_CHECK_ARGS[@]}"
    else
        cargo test --frozen
    fi
fi

for archive_file in "\${BINARY_RELEASE_ARCHIVE_FILES[@]}"; do
    IFS=: read -r source_path destination_path file_mode <<< "\$archive_file"
    [ -n "\$source_path" ] || { echo "Invalid archive file spec: \$archive_file" >&2; exit 1; }
    [ -n "\$destination_path" ] || { echo "Invalid archive file spec: \$archive_file" >&2; exit 1; }
    [ -n "\$file_mode" ] || file_mode=644
    case "\$source_path" in
        /*|../*|*/../*|*/..) echo "Archive source must be relative and stay inside the source tree: \$source_path" >&2; exit 1 ;;
    esac
    case "\$destination_path" in
        /*|../*|*/../*|*/..) echo "Archive destination must be relative and stay inside archive: \$destination_path" >&2; exit 1 ;;
    esac
    case "\$file_mode" in
        *[!0-7]*|''|?????*) echo "Archive mode must be octal: \$file_mode" >&2; exit 1 ;;
    esac
    [ -f "\$source_path" ] || { echo "Archive source not found: \$source_path" >&2; exit 1; }
    install -Dm"\$file_mode" "\$source_path" "/output/\$destination_path"
done
EOF

    chmod +x "$container_script" "$builder_script"

    log_info "Building ${PKGNAME} ${pkgver} (${arch}) with ${runtime}"
    "$runtime" run --rm \
        -e HOST_UID="$(id -u)" \
        -e HOST_GID="$(id -g)" \
        -v "$REPO_ROOT:/work:ro" \
        -v "$output_dir:/output" \
        -v "$container_script:/container.sh:ro" \
        -v "$builder_script:/builder.sh:ro" \
        "$ARCH_BASE_DEVEL_IMAGE" \
        bash /container.sh

    local archive_spec
    local destination_path
    for archive_spec in "${BINARY_RELEASE_ARCHIVE_FILES[@]}"; do
        IFS=: read -r _source_path destination_path _file_mode <<< "$archive_spec"
        archive_destinations+=("$destination_path")
    done

    tar -C "$output_dir" -czf "$asset_path" "${archive_destinations[@]}"
    rm -rf "$tmp_root"
}
