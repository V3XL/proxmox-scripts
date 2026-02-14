#!/bin/bash
set -e

# Paths
CPU_SCRIPT="/usr/local/bin/cpu_power_saver.sh"
SAFE_REBOOT_SCRIPT="/usr/local/bin/safe_reboot.sh"
SAFE_REBOOT_CLI="/usr/local/bin/safe-reboot"

CPU_SERVICE="/etc/systemd/system/cpu_power_saver.service"
SAFE_REBOOT_SERVICE="/etc/systemd/system/safe_reboot.service"

# Check installed
CPU_INSTALLED=0
SAFE_INSTALLED=0
[[ -f "$CPU_SERVICE" ]] && CPU_INSTALLED=1
[[ -f "$SAFE_REBOOT_SERVICE" ]] && SAFE_INSTALLED=1

# Prepare whiptail options
OPTIONS=(
    "CPU Power Saver" "" $CPU_INSTALLED
    "Safe Reboot --post (service only runs POST mode)" "" $SAFE_INSTALLED
)

# Launch TUI
SELECTION=$(whiptail --title "Select services to install" \
    --checklist "Use SPACE to toggle, ENTER to confirm" 15 70 5 \
    "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

# Exit if canceled
[[ $? -ne 0 ]] && echo "Canceled." && exit 1

# Convert selection to array
SELECTION=($SELECTION)

# Functions
install_cpu() {
    cp scripts/cpu_power_saver.sh "$CPU_SCRIPT"
    chmod +x "$CPU_SCRIPT"

    cat > "$CPU_SERVICE" <<EOF
[Unit]
Description=CPU Power Saver Service
After=network.target

[Service]
ExecStart=$CPU_SCRIPT
Restart=always
User=root
Group=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now cpu_power_saver.service
    echo "CPU Power Saver installed and started."
}

install_safe_reboot() {
    cp scripts/safe_reboot.sh "$SAFE_REBOOT_SCRIPT"
    chmod +x "$SAFE_REBOOT_SCRIPT"

    # Service only runs POST-reboot tasks
    cat > "$SAFE_REBOOT_SERVICE" <<EOF
[Unit]
Description=Safe Reboot Post-Reboot Service
After=network.target

[Service]
ExecStart=$SAFE_REBOOT_SCRIPT --post
Restart=no
User=root
Group=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now safe_reboot.service
    echo "Safe Reboot --post service installed and enabled."

    # CLI wrapper for manual PRE/POST execution
    cat > "$SAFE_REBOOT_CLI" <<'EOF'
#!/bin/bash
# Always default to PRE mode if no argument given
ARG="${1:---pre}"
exec /usr/local/bin/safe_reboot.sh "$ARG"
EOF
    chmod +x "$SAFE_REBOOT_CLI"
    echo "CLI wrapper 'safe-reboot' created. Use it manually for pre-reboot tasks."
}

remove_cpu() {
    systemctl stop cpu_power_saver.service 2>/dev/null || true
    systemctl disable cpu_power_saver.service 2>/dev/null || true
    rm -f "$CPU_SERVICE" "$CPU_SCRIPT"
    echo "CPU Power Saver removed."
}

remove_safe_reboot() {
    systemctl stop safe_reboot.service 2>/dev/null || true
    systemctl disable safe_reboot.service 2>/dev/null || true
    rm -f "$SAFE_REBOOT_SERVICE" "$SAFE_REBOOT_SCRIPT" "$SAFE_REBOOT_CLI"
    echo "Safe Reboot removed."
}

# Apply selections
for name in "CPU Power Saver" "Safe Reboot --post (service only runs POST mode)"; do
    if [[ " ${SELECTION[*]} " == *"$name"* ]]; then
        case "$name" in
            "CPU Power Saver") [[ $CPU_INSTALLED -eq 0 ]] && install_cpu ;;
            "Safe Reboot --post (service only runs POST mode)") [[ $SAFE_INSTALLED -eq 0 ]] && install_safe_reboot ;;
        esac
    else
        case "$name" in
            "CPU Power Saver") [[ $CPU_INSTALLED -eq 1 ]] && remove_cpu ;;
            "Safe Reboot --post (service only runs POST mode)") [[ $SAFE_INSTALLED -eq 1 ]] && remove_safe_reboot ;;
        esac
    fi
done

echo "Deployment complete."
echo "Use 'safe-reboot --pre' manually to perform pre-reboot tasks and auto-reboot the node."
