cp scripts/cpu_power_saver.sh /usr/local/bin/
chmod +x /usr/local/bin/cpu_power_saver.sh

SERVICE_FILE="/etc/systemd/system/cpu_power_saver.service"

echo "[Unit]
Description=CPU Power Saver Service
After=network.target

[Service]
ExecStart=/usr/local/bin/cpu_power_saver.sh
Restart=always
User=root
Group=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
Environment=HOME=/root

[Install]
WantedBy=multi-user.target" > $SERVICE_FILE

systemctl daemon-reload
systemctl start cpu_power_saver.service
systemctl enable cpu_power_saver.service
