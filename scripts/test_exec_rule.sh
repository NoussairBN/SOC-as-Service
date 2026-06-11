#!/bin/bash
# Test POST exec log line - should now trigger rule 100043 via if_sid 31108
LOG_LINE='10.0.1.21 - - [11/Jun/2026:20:09:48 +0000] "POST /vulnerabilities/exec/ HTTP/1.1" 200 2253 "http://localhost:8080/vulnerabilities/exec/" "Mozilla/5.0"'

echo "=== Test avec regles actuelles (avant deploy) ==="
echo "$LOG_LINE" | /var/ossec/bin/wazuh-logtest 2>&1 | grep -E 'id:|level:|description:|Phase 3'
