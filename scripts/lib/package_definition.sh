#!/bin/bash

PACKAGE_SPEC_SUPPORTED_VERSION=1

package_definition_path() {
    local package_dir=$1
    local candidate="${package_dir}/package.conf"

    if [ -f "$candidate" ]; then
        printf '%s' "$candidate"
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
    find "$package_root" -mindepth 2 -maxdepth 2 -name package.conf -type f | sort
}

validate_package_spec_data_only() {
    local spec_path=$1
    local line
    local line_number=0
    local in_array=false
    local function_definition_re='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(][)][[:space:]]*[{]'
    local unquoted
    local assignment_name
    local assignment_tail

    [ -f "$spec_path" ] || {
        printf 'PackageSpec file not found: %s\n' "$spec_path" >&2
        return 1
    }

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))

        [[ "$line" =~ ^[[:space:]]*($|#) ]] && continue

        case "$line" in
            *'$('*|*'`'*|*'<('*|*'>('*)
                printf 'Unsupported command or process substitution in %s:%s\n' "$spec_path" "$line_number" >&2
                return 1
                ;;
        esac

        if package_spec_has_unsafe_expansion "$line"; then
            printf 'Unsupported unquoted variable expansion in %s:%s\n' "$spec_path" "$line_number" >&2
            return 1
        fi

        if [[ "$line" =~ $function_definition_re ]]; then
            printf 'Unsupported function definition in %s:%s\n' "$spec_path" "$line_number" >&2
            return 1
        fi

        unquoted=$(package_spec_unquoted_shell "$line") || {
            printf 'Unterminated quote in %s:%s\n' "$spec_path" "$line_number" >&2
            return 1
        }

        if [[ "$unquoted" == *[';'\<\>\&]* ]] || [[ "$unquoted" == *'|'* ]]; then
            printf 'Unsupported shell operator in %s:%s\n' "$spec_path" "$line_number" >&2
            return 1
        fi

        if [ "$in_array" = true ]; then
            if [[ "$unquoted" =~ [^[:space:]\)] ]]; then
                printf 'Unsupported unquoted array content in %s:%s\n' "$spec_path" "$line_number" >&2
                return 1
            fi

            [[ "$unquoted" == *')'* ]] && in_array=false
            continue
        fi

        if ! [[ "$unquoted" =~ ^[[:space:]]*[A-Z][A-Z0-9_]*[[:space:]]*= ]]; then
            printf 'PackageSpec entries must be assignments in %s:%s\n' "$spec_path" "$line_number" >&2
            return 1
        fi

        assignment_name=${unquoted%%=*}
        assignment_name=${assignment_name//[[:space:]]/}
        if ! package_spec_variable_allowed "$assignment_name"; then
            printf 'Unsupported PackageSpec variable in %s:%s: %s\n' "$spec_path" "$line_number" "$assignment_name" >&2
            return 1
        fi

        assignment_tail=${unquoted#*=}
        if [[ "$assignment_tail" =~ [^[:space:]\(\)]+[[:space:]]+[^[:space:]\)]+ ]]; then
            printf 'Unsupported extra tokens after assignment in %s:%s\n' "$spec_path" "$line_number" >&2
            return 1
        fi

        if [[ "$assignment_tail" == *'('* && "$assignment_tail" != *')'* ]]; then
            in_array=true
        fi
    done < "$spec_path"

    if [ "$in_array" = true ]; then
        printf 'Unterminated array assignment in %s\n' "$spec_path" >&2
        return 1
    fi
}

package_spec_has_unsafe_expansion() {
    local line=$1
    local quote=""
    local index
    local char

    for ((index = 0; index < ${#line}; index++)); do
        char=${line:index:1}

        if [ -n "$quote" ]; then
            if [ "$quote" = "'" ]; then
                [ "$char" = "'" ] && quote=""
            elif [ "$quote" = '"' ]; then
                if [ "$char" = '\\' ]; then
                    index=$((index + 1))
                    continue
                fi
                [ "$char" = '"' ] && quote=""
                [ "$char" = '$' ] && return 0
            fi
            continue
        fi

        case "$char" in
            "'") quote="'" ;;
            '"') quote='"' ;;
            '$') return 0 ;;
        esac
    done

    return 1
}

package_spec_unquoted_shell() {
    local line=$1
    local quote=""
    local output=""
    local index
    local char

    for ((index = 0; index < ${#line}; index++)); do
        char=${line:index:1}

        if [ -n "$quote" ]; then
            if [ "$quote" = "'" ]; then
                [ "$char" = "'" ] && quote=""
            elif [ "$quote" = '"' ]; then
                if [ "$char" = '\\' ]; then
                    output+=" "
                    index=$((index + 1))
                    [ "$index" -lt "${#line}" ] && output+=" "
                    continue
                fi
                [ "$char" = '"' ] && quote=""
            fi

            output+=" "
            continue
        fi

        case "$char" in
            "'")
                quote="'"
                output+=" "
                ;;
            '"')
                quote='"'
                output+=" "
                ;;
            '#')
                if [[ "$output" =~ (^|[[:space:]])$ ]]; then
                    break
                fi
                return 1
                ;;
            *)
                output+="$char"
                ;;
        esac
    done

    [ -z "$quote" ] || return 1
    printf '%s' "$output"
}

package_spec_variable_allowed() {
    case "$1" in
        PACKAGE_SPEC_VERSION|PKGNAME|PACKAGE_TEMPLATE|UPSTREAM_TYPE|PKGDESC|URL|LICENSES|ARCHES|DEPENDS|MAKEDEPENDS|CHECKDEPENDS|OPTDEPENDS|OPTIONS|PROVIDES|CONFLICTS|VALIDPGPKEYS|PACKAGING_REPO_URL) ;;
        UPSTREAM_REPO_USER|UPSTREAM_REPO_NAME|UPSTREAM_TAG_PREFIX|UPSTREAM_RELEASE_TAG_PREFIX|UPSTREAM_ALLOW_PRERELEASE) ;;
        ASSET_SELECTOR_*|UPSTREAM_ASSET_NAME_*|SOURCE_RENAME|SOURCE_RENAME_*) ;;
        BINARY_NAME|BINARY_SOURCE_PATH|INSTALL_BIN_PATH|WRAPPER_SOURCE_PATH|WRAPPER_INSTALL_PATH|WRAPPER_MODE) ;;
        LOCAL_FILES|PATCH_FILES|DOC_FILES|LICENSE_FILES) ;;
        INSTALL_MODE|INSTALL_HINTS|INSTALL_FILE) ;;
        SERVICE_MODE|SERVICE_SCOPE|SERVICE_NAME|SERVICE_FILE|SERVICE_EXEC|SERVICE_RESTART|SERVICE_RESTART_SEC) ;;
        DEB_RELOCATE_USR_LOCAL|APPIMAGE_APPDIR_NAME|APPIMAGE_INSTALL_DIR|DESKTOP_CANDIDATES|ICON_CANDIDATES|DESKTOP_EXEC_REWRITE|DESKTOP_NAME_REWRITE) ;;
        SOURCE_DIR|BUILD_DIR|MESON_OPTIONS|RUN_CHECK|CHECK_ARGS) ;;
        BINARY_RELEASE_ENABLED|BINARY_RELEASE_TEMPLATE|BINARY_RELEASE_REV|BINARY_RELEASE_VERSION_TEMPLATE|BINARY_RELEASE_TAG_PREFIX|BINARY_RELEASE_REPO|BINARY_RELEASE_ARCHES) ;;
        BINARY_RELEASE_ASSET_*|BINARY_RELEASE_UPSTREAM_TYPE|BINARY_RELEASE_UPSTREAM_REPO_USER|BINARY_RELEASE_UPSTREAM_REPO_NAME|BINARY_RELEASE_UPSTREAM_TAG_PREFIX|BINARY_RELEASE_SOURCE_DIR) ;;
        BINARY_RELEASE_PATCH_FILES|BINARY_RELEASE_MAKEDEPENDS|BINARY_RELEASE_CARGO_FETCH_ARGS|BINARY_RELEASE_CARGO_BUILD_ARGS|BINARY_RELEASE_CARGO_CHECK_ARGS|BINARY_RELEASE_RUN_CHECK|BINARY_RELEASE_ARCHIVE_FILES) ;;
        PERSIST_STATE_KEYS|TEST_PATHS|TEST_EXECUTABLES|TEST_COMMANDS) ;;
        *) return 1 ;;
    esac

    return 0
}

package_spec_pkgname_from_file() {
    local spec_path=$1
    local line
    local name

    [ -f "$spec_path" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            PKGNAME=*)
                name=${line#PKGNAME=}
                name=${name%%#*}
                name=${name//[[:space:]]/}
                name=${name%\'}
                name=${name#\'}
                name=${name%\"}
                name=${name#\"}
                printf '%s' "$name"
                return 0
                ;;
        esac
    done < "$spec_path"
}
