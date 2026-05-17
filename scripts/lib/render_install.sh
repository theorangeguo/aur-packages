#!/bin/bash

prepare_workspace_package_files() {
    local workspace=$1
    local copied_path
    local relative_path

    reset_workspace_state

    for relative_path in "${LOCAL_FILES[@]}"; do
        [ -n "$relative_path" ] || continue
        copied_path=$(copy_package_asset "$PACKAGE_DIR" "$relative_path" "$workspace")
        register_common_source_file "$(basename "$copied_path")"
    done

    for relative_path in "${PATCH_FILES[@]}"; do
        [ -n "$relative_path" ] || continue
        copied_path=$(copy_package_asset "$PACKAGE_DIR" "$relative_path" "$workspace")
        register_common_source_file "$(basename "$copied_path")"
    done

    case "$SERVICE_MODE" in
        generated)
            WORKSPACE_SERVICE_FILE_NAME=$SERVICE_NAME
            generate_service_file > "${workspace}/${WORKSPACE_SERVICE_FILE_NAME}"
            register_common_source_file "$WORKSPACE_SERVICE_FILE_NAME"
            ;;
        static)
            copied_path=$(copy_package_asset "$PACKAGE_DIR" "$SERVICE_FILE" "$workspace")
            WORKSPACE_SERVICE_FILE_NAME=$(basename "$copied_path")
            register_common_source_file "$WORKSPACE_SERVICE_FILE_NAME"
            ;;
    esac

    case "$INSTALL_MODE" in
        generated)
            WORKSPACE_INSTALL_FILE_NAME="${PKGNAME}.install"
            generate_install_script > "${workspace}/${WORKSPACE_INSTALL_FILE_NAME}"
            register_workspace_sync_file "$WORKSPACE_INSTALL_FILE_NAME"
            ;;
        static)
            copied_path=$(copy_package_asset "$PACKAGE_DIR" "$INSTALL_FILE" "$workspace")
            WORKSPACE_INSTALL_FILE_NAME=$(basename "$copied_path")
            register_workspace_sync_file "$WORKSPACE_INSTALL_FILE_NAME"
            ;;
    esac
}

generate_service_file() {
    cat <<EOF
[Unit]
Description=${PKGNAME} Service
After=network.target

[Service]
Type=simple
ExecStart=${SERVICE_EXEC}
Restart=${SERVICE_RESTART}
RestartSec=${SERVICE_RESTART_SEC}

[Install]
WantedBy=$( [ "$SERVICE_SCOPE" = "user" ] && printf 'default.target' || printf 'multi-user.target' )
EOF
}

generate_install_script() {
    cat <<EOF
post_install() {
    echo ":: Packaging issues? Report at: https://github.com/orange-guo/aur-packages"
EOF

    local hint
    for hint in "${INSTALL_HINTS[@]}"; do
        printf '    echo %q\n' "$hint"
    done

    if [ "$SERVICE_MODE" != "none" ]; then
        cat <<EOF
    echo ""
    echo ":: Service Management"
EOF

        if [ "$SERVICE_SCOPE" = "user" ]; then
            cat <<EOF
    echo "   > User Level (Recommended):"
    echo "     systemctl --user enable --now ${SERVICE_NAME}"
    echo "   > System Level:"
    echo "     (System Service is not available for this package)"
EOF
        else
            cat <<EOF
    echo "   > System Level:"
    echo "     systemctl enable --now ${SERVICE_NAME}"
EOF
        fi
    fi

    cat <<'EOF'
}

post_upgrade() {
EOF

    if [ "$SERVICE_MODE" != "none" ]; then
        if [ "$SERVICE_SCOPE" = "user" ]; then
            cat <<EOF
    echo ":: Service Management"
    echo "   > User Level:"
    echo "     systemctl --user daemon-reload"
    echo "     systemctl --user restart ${SERVICE_NAME}"
    echo "   > System Level:"
    echo "     (System Service is not available for this package)"
EOF
        else
            cat <<EOF
    echo ":: Service Management"
    echo "   > System Level:"
    echo "     systemctl daemon-reload"
    echo "     systemctl restart ${SERVICE_NAME}"
EOF
        fi
    else
        echo "    :"
    fi

    cat <<'EOF'
}

post_remove() {
EOF

    if [ "$SERVICE_MODE" != "none" ]; then
        if [ "$SERVICE_SCOPE" = "user" ]; then
            cat <<EOF
    echo ":: Service Management"
    echo "   > User Level:"
    echo "     The service file has been removed. Stop the service if running:"
    echo "     systemctl --user stop ${SERVICE_NAME}"
    echo "   > System Level:"
    echo "     (System Service is not available for this package)"
EOF
        else
            cat <<EOF
    echo ":: Service Management"
    echo "   > System Level:"
    echo "     The service file has been removed. Stop the service if running:"
    echo "     systemctl stop ${SERVICE_NAME}"
EOF
        fi
    else
        echo "    :"
    fi

    cat <<'EOF'
}
EOF
}
