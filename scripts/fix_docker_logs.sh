#!/bin/bash
# Fix: Stream Docker DVWA Apache logs to host filesystem so Wazuh can read them

set -e

echo "=== Setting up Docker log forwarding to host ==="

# 1. Create the log files on host (touch so they exist)
touch /var/log/dvwa-access.log
touch /var/log/dvwa-error.log
chown root:adm /var/log/dvwa-access.log /var/log/dvwa-error.log
chmod 644 /var/log/dvwa-access.log /var/log/dvwa-error.log

# 2. Create a systemd service that tails the Docker logs and writes to host
cat > /etc/systemd/system/dvwa-log-forwarder.service << 'EOF'
[Unit]
Description=DVWA Docker Apache Log Forwarder to Host
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/bin/bash -c 'docker exec dvwa tail -F /var/log/apache2/access.log >> /var/log/dvwa-access.log 2>&1'

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable and start the service
systemctl daemon-reload
systemctl enable dvwa-log-forwarder
systemctl restart dvwa-log-forwarder

sleep 2
systemctl status dvwa-log-forwarder --no-pager | head -10

# 4. Update ossec.conf to point to the correct access log file
# Replace /var/log/apache2/access.log with /var/log/dvwa-access.log
sed -i 's|<location>/var/log/apache2/access.log</location>|<location>/var/log/dvwa-access.log</location>|g' /var/ossec/etc/ossec.conf
sed -i 's|<location>/var/log/dvwa-apache.log</location>|<!-- disabled: error log only --> <!-- <location>/var/log/dvwa-apache.log</location> -->|g' /var/ossec/etc/ossec.conf

echo ""
echo "=== Current ossec.conf localfile section ==="
grep -A3 "localfile" /var/ossec/etc/ossec.conf | grep -v "^--$"

# 5. Restart wazuh-agent to pick up new config
echo ""
echo "=== Restarting wazuh-agent ==="
systemctl restart wazuh-agent
sleep 5
tail -10 /var/ossec/logs/ossec.log

echo ""
echo "=== Done! Testing: making a request to DVWA... ==="
curl -s http://localhost/vulnerabilities/xss_r/?name=%3Cscript%3Etest%3C/script%3E -o /dev/null
sleep 2
echo "Last 3 lines in dvwa-access.log:"
tail -3 /var/log/dvwa-access.log
