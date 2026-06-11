#!/bin/bash
# Get Wazuh API users and add new agent with correct name

# Get the API users
echo "=== Wazuh API users ==="
python3 << 'PYEOF'
import sqlite3
conn = sqlite3.connect('/var/ossec/api/configuration/security/rbac.db')
users = conn.execute('SELECT id, username FROM users').fetchall()
for u in users:
    print(f"  ID:{u[0]} Username:{u[1]}")
PYEOF
