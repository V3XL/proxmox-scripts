#!/bin/bash
set -e

# Available scripts/services
declare -A SERVICES=(
    ["CPU Power Saver"]="/usr/local/bin/cpu_power_saver.sh"
    ["Safe Reboot Post"]="/usr/local/bin/safe-reboot.sh --post"
)

# Corresponding systemd service names
declare -A SERVICE_UNITS=(
    ["CPU Power Saver"]="cpu_power_saver.service"
    ["Safe Reboot Post"]="safe-reboot-post.service"
)

# Ensure scripts exist
mkdir -p /usr/local/bin
cp scripts/cpu_power_saver.sh /usr/local/bin/
chmod +x /usr/local/bin/cpu_power_saver.sh

cp scripts/safe-reboot.sh /usr/local/bin/
chmod +x /usr/local/bin/safe-reboot.sh

# Build menu items with checked status based on systemctl
MENU=()
for name in "${!SERVICES[@]}"; do
    unit=${SERVICE_UNITS[$name]}
    if systemctl is-enabled "$unit" &>/dev/null; then
        MENU+=("$name" "" "on")
    else
        MENU+=("$name" "" "off")
    fi
done

# Use whiptail for checkbox menu (if not installed, install or use dialog)
CHOICES=$(whiptail --title "Select Services to Deploy" \
    --checklist "Use SPACE to toggle, ENTER to apply" 15 60 6 \
    "${MENU[@]}" 3>&1 1>&2 2>&3)

# Convert choices into array
read -r -a SELECTED <<< "$CHOICES"

# Apply changes
for name in "${!SERVICES[@]}"; do
    unit=${SERVICE_UNITS[$name]}
    script=${SERVICES[$name]}

    if [[ " ${SELECTED[*]} " =~ " $name " ]]; then
        # Install/start if not enabled
        if ! systemctl is-enabled "$unit" &>/dev/null; then
            echo "Installing and starting $unit..."
            echo "[Unit]
Description=$name
After=network.target

[Service]
ExecStart=$script
Restart=always
User=root
Group=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
Environment=HOME=/root

[Install]
WantedBy=multi-user.target" > "/etc/systemd/system/$unit"

            systemctl daemon-reload
            systemctl enable "$unit"
            systemctl start "$unit"
        else
            echo "$unit already installed and running."
        fi
    else
        # Stop/remove if currently enabled
        if systemctl is-enabled "$unit" &>/dev/null; then
            echo "Stopping and disabling $unit..."
            systemctl stop "$unit"
            systemctl disable "$unit"
            rm -f "/etc/systemd/system/$unit"
            systemctl daemon-reload
        fi
    fi
done

echo "Deployment complete."
