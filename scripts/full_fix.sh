#!/bin/bash
# Full fix: rules + agent name
set -e

echo "=== 1. Deploying fixed custom rules ==="
cp /tmp/custom_rules.xml /var/ossec/etc/rules/custom_rules.xml
chown wazuh:wazuh /var/ossec/etc/rules/custom_rules.xml
chmod 660 /var/ossec/etc/rules/custom_rules.xml
echo "Rules deployed."

echo ""
echo "=== 2. Fixing agent name (re-registering agent 002 as 'dvwa') ==="
# The agent at 10.0.2.98 has client.keys: 002 dvwa any <key>
# The manager had it as 'metasploitable'. We need to add it back as 'dvwa'.
# Get the key that's on the agent's side (from manager client.keys backup or re-issue)

# Add agent via API
TOKEN=$(curl -sk -X POST \
  "https://localhost:55000/security/user/authenticate?raw=true" \
  -H "Content-Type: application/json" \
  -u "wazuh:WZxikZgP4D3J3ejlV.lT1*hEONiukeIE")
echo "Got API token: ${TOKEN:0:20}..."

RESULT=$(curl -sk -X POST https://localhost:55000/agents \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "dvwa", "ip": "any"}')
echo "Agent creation: $RESULT"

AGENT_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)
echo "New Agent ID: $AGENT_ID"

# Extract the key for this new agent
KEY_RESULT=$(curl -sk -X GET "https://localhost:55000/agents/$AGENT_ID/key" \
  -H "Authorization: Bearer $TOKEN")
echo "Key: $KEY_RESULT"
NEW_KEY=$(echo "$KEY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['affected_items'][0]['key'])" 2>/dev/null)
echo "Agent key extracted: ${NEW_KEY:0:20}..."

echo ""
echo "=== 3. Restarting Wazuh Manager ==="
/var/ossec/bin/wazuh-control restart

echo ""
echo "=== 4. Agent key to paste on the agent machine ==="
echo "Run on 10.0.2.98:"
echo "  sudo /var/ossec/bin/manage_agents -i '$NEW_KEY'"
echo "  sudo systemctl restart wazuh-agent"
echo ""
echo "Done! Agent ID: $AGENT_ID, Key prefix: ${NEW_KEY:0:30}..."
