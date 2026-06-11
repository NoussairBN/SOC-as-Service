#!/bin/bash
# Step 1: Restore agent 002 (dvwa) in manager client.keys
echo "002 dvwa any 3b1ba1044a482f7f35ceb0846ccca03f1788c8e7181b2f96cea24689147bdba4" >> /var/ossec/etc/client.keys
chown wazuh:wazuh /var/ossec/etc/client.keys
chmod 640 /var/ossec/etc/client.keys
echo "=== client.keys after fix ==="
cat /var/ossec/etc/client.keys

# Step 2: Deploy fixed custom rules
cp /tmp/custom_rules.xml /var/ossec/etc/rules/custom_rules.xml
chown wazuh:wazuh /var/ossec/etc/rules/custom_rules.xml
chmod 660 /var/ossec/etc/rules/custom_rules.xml
echo "Rules deployed."

# Step 3: Restart manager
echo "Restarting Wazuh Manager..."
/var/ossec/bin/wazuh-control restart
echo "Done!"
