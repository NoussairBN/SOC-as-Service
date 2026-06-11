#!/bin/bash
# Fix script: Re-register agent with correct name + fix ossec.conf log path
# Run on: Wazuh Manager (10.1.1.133)
set -e

echo "=== Step 1: Re-registering the DVWA agent with correct name ==="
# Add agent via manage_agents non-interactively using expect
AGENT_NAME="dvwa-metasploitable"
AGENT_IP="any"

# Use the API to add the agent
TOKEN=$(curl -sk -u admin:SecureSOC2024! \
  https://localhost:55000/security/user/authenticate \
  -X POST | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['token'])")

echo "Got API token"

# Create the agent
RESULT=$(curl -sk -X POST https://localhost:55000/agents \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$AGENT_NAME\", \"ip\": \"$AGENT_IP\"}")

echo "Agent creation result: $RESULT"
AGENT_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['id'])")
echo "New Agent ID: $AGENT_ID"

# Get the key for the new agent
KEY_RESULT=$(curl -sk -X GET "https://localhost:55000/agents/$AGENT_ID/key" \
  -H "Authorization: Bearer $TOKEN")
echo "Key result: $KEY_RESULT"

echo ""
echo "=== Step 2: Current agents list ==="
/var/ossec/bin/manage_agents -l

echo ""
echo "Done!"
