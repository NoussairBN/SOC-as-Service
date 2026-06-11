#!/bin/bash
# Fix: Register agent 002 with proper name 'dvwa-apache' on manager
# Then sync the key back to the agent

set -e

echo "=== Current state ==="
cat /var/ossec/etc/client.keys

echo ""
echo "=== Removing agent 002 entry from manager ==="
# Keep only agent 001
grep "^001 " /var/ossec/etc/client.keys > /tmp/keys_backup.txt

# Add agent 002 with new name via manage_agents non-interactively  
# We will use manage_agents with piped input
RESULT=$(printf 'A\ndvwa-apache\nany\n\ny\nE\n002\nQ\n' | /var/ossec/bin/manage_agents 2>&1)
echo "$RESULT"

echo ""
echo "=== Final client.keys ==="
cat /var/ossec/etc/client.keys
