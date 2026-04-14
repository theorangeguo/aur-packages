#!/bin/bash

prepare_aur_repo() {
    local package_name=$1
    local aur_dir=$2
    local aur_readonly_url="https://aur.archlinux.org/${package_name}.git"
    local aur_package_url="https://aur.archlinux.org/packages/${package_name}"
    local package_status

    if git clone "$aur_readonly_url" "$aur_dir" >/dev/null 2>&1; then
        AUR_REPO_DIR=$aur_dir
        return 0
    fi

    require_cmd curl
    package_status=$(curl -sS -L -o /dev/null -w '%{http_code}' "$aur_package_url" || true)

    case "$package_status" in
        200)
            die "Failed to clone existing AUR repository for ${package_name}"
            ;;
        404)
            ;;
        *)
            die "Could not determine AUR package status for ${package_name} (HTTP ${package_status:-unknown})"
            ;;
    esac

    log_info "AUR repository not found for ${package_name}; treating this as a new package."
    git init -q -b master "$aur_dir"
    AUR_REPO_DIR=$aur_dir
}

load_aur_state() {
    local pkgbuild_path="${AUR_REPO_DIR}/PKGBUILD"

    if [ -f "$pkgbuild_path" ]; then
        AUR_CURRENT_VER=$(pkgbuild_var_from_file "$pkgbuild_path" "pkgver")
        AUR_CURRENT_REL=$(pkgbuild_var_from_file "$pkgbuild_path" "pkgrel")
    else
        AUR_CURRENT_VER=""
        AUR_CURRENT_REL=0
    fi

    AUR_CURRENT_REL=${AUR_CURRENT_REL:-0}
}

sync_workspace_to_aur_repo() {
    local workspace=$1
    shift
    local sync_files=("$@")
    local manifest_file="${AUR_REPO_DIR}/.aur-managed-files"

    if [ -f "$manifest_file" ]; then
        while IFS= read -r managed_file; do
            [ -n "$managed_file" ] || continue
            if ! sync_file_list_contains "$managed_file" "${sync_files[@]}"; then
                rm -f "${AUR_REPO_DIR}/${managed_file}"
            fi
        done < "$manifest_file"
    fi

    local relative_path
    for relative_path in "${sync_files[@]}"; do
        cp "${workspace}/${relative_path}" "${AUR_REPO_DIR}/${relative_path}"
    done

    printf '%s\n' "${sync_files[@]}" > "$manifest_file"

    git -C "$AUR_REPO_DIR" add -A
}

aur_repo_has_staged_changes() {
    ! git -C "$AUR_REPO_DIR" diff --cached --quiet
}

aur_repo_has_packaging_changes() {
    local staged_path
    while IFS= read -r staged_path; do
        [ -n "$staged_path" ] || continue
        [ "$staged_path" = ".aur-managed-files" ] && continue
        return 0
    done < <(git -C "$AUR_REPO_DIR" diff --cached --name-only)

    return 1
}

sync_file_list_contains() {
    local needle=$1
    shift
    local candidate
    for candidate in "$@"; do
        [ "$candidate" = "$needle" ] && return 0
    done
    return 1
}
