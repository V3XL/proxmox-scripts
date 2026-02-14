#!/bin/bash

# Paths
CPU_SCRIPT="/usr/local/bin/cpu_power_saver.sh"
SAFE_REBOOT_SCRIPT="/usr/local/bin/safe_reboot.sh"
SAFE_REBOOT_CLI="/usr/local/bin/safe-reboot"

CPU_SERVICE="/etc/systemd/system/cpu_power_saver.service"
SAFE_REBOOT_SERVICE="/etc/systemd/system/safe_reboot.service"

# Available options
OPTIONS=("CPU Power Saver" "Safe Reboot --post")

# Detect installed services
INSTALLED=()
[[ -f "$CPU_SERVICE" ]] && INSTALLED+=("CPU Power Saver")
[[ -f "$SAFE_REBOOT_SERVICE" ]] && INSTALLED+=("Safe Reboot --post")

echo "Select services to install (currently installed: ${INSTALLED[*]}):"
echo "Enter numbers separated by spaces (e.g., 1 2), or leave blank to keep current:"

# Show numbered list
for i in "${!OPTIONS[@]}"; do
    num=$((i+1))
    name="${OPTIONS[i]}"
    if [[ " ${INSTALLED[*]} " == *"$name"* ]]; then
        echo "$num) [x] $name"
    else
        echo "$num) [ ] $name"
    fi
done

read -rp "Selection: " selection

# Parse selection into array of numbers
read -ra SELECTED <<< "$selection"

# Functions
install_cpu() {
    cp scripts/cpu_power_saver.sh "$CPU_SCRIPT"
    chmod +x "$CPU_SCRIPT"

    echo "[Unit]
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
WantedBy=multi-user.target" > "$CPU_SERVICE"

    systemctl daemon-reload
    systemctl enable --now cpu_power_saver.service
    echo "CPU Power Saver installed and started."
}

install_safe_reboot() {
    cp scripts/safe_reboot.sh "$SAFE_REBOOT_SCRIPT"
    chmod +x "$SAFE_REBOOT_SCRIPT"

    echo "[Unit]
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
WantedBy=multi-user.target" > "$SAFE_REBOOT_SERVICE"

    systemctl daemon-reload
    systemctl enable --now safe_reboot.service
    echo "Safe Reboot --post service installed and enabled."

    # CLI wrapper
    echo "#!/bin/bash
ARG=\"\${1:---pre}\"
$SAFE_REBOOT_SCRIPT \"\$ARG\"" > "$SAFE_REBOOT_CLI"
    chmod +x "$SAFE_REBOOT_CLI"
    echo "CLI wrapper 'safe-reboot' created."
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

# Apply selection
for i in "${!OPTIONS[@]}"; do
    num=$((i+1))
    name="${OPTIONS[i]}"

    if [[ " ${SELECTED[*]} " == *"$num"* ]]; then
        # Install if not installed
        if [[ ! " ${INSTALLED[*]} " == *"$name"* ]]; then
            case "$name" in
                "CPU Power Saver") install_cpu ;;
                "Safe Reboot --post") install_safe_reboot ;;
            esac
        fi
    else
        # Remove if installed
        if [[ " ${INSTALLED[*]} " == *"$name"* ]]; then
            case "$name" in
                "CPU Power Saver") remove_cpu ;;
                "Safe Reboot --post") remove_safe_reboot ;;
            esac
        fi
    fi
done

echo "Deployment complete."
