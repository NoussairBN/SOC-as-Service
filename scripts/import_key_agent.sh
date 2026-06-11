#!/bin/bash
# Import the new key on the agent machine and restart
NEW_KEY="MDAyIGR2d2EtYXBhY2hlIDEwLjAuMi45OCBkYWExNzJhYzVkZjEyYTk4OTU2ZjZmOWIxMTE5OTc1NzdhMWQxYjBmZTE2ZDdlZjI2MzNiYzE2NzliYWJhZGNi"

echo "=== Importing new agent key ==="
printf "I\n${NEW_KEY}\ny\nQ\n" | /var/ossec/bin/manage_agents
echo ""
echo "=== client.keys after import ==="
cat /var/ossec/etc/client.keys
echo ""
echo "=== Restarting wazuh-agent ==="
systemctl restart wazuh-agent
sleep 5
systemctl status wazuh-agent --no-pager | head -8
echo ""
echo "=== Checking connection to manager ==="
tail -10 /var/ossec/logs/ossec.log
