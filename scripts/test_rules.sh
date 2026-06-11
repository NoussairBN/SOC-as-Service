#!/bin/bash
# Test XSS log line through wazuh-logtest to see which rule fires

XSS_LINE='10.0.1.21 - - [11/Jun/2026:20:50:00 +0000] "GET /vulnerabilities/xss_r/?name=%3Cscript%3Ealert(%27HACKED%27)%3C/script%3E HTTP/1.1" 200 1780 "-" "Mozilla/5.0"'
LFI_LINE='10.0.1.21 - - [11/Jun/2026:20:50:01 +0000] "GET /vulnerabilities/fi/?page=../../../../etc/passwd HTTP/1.1" 200 1422 "-" "Mozilla/5.0"'

echo "=== Testing XSS ==="
echo "$XSS_LINE" | /var/ossec/bin/wazuh-logtest -U 'apache' 2>&1 | grep -E 'Rule:|Description:|decoder|Matched'

echo ""
echo "=== Testing LFI ==="
echo "$LFI_LINE" | /var/ossec/bin/wazuh-logtest -U 'apache' 2>&1 | grep -E 'Rule:|Description:|decoder|Matched'

echo ""
echo "=== Full XSS wazuh-logtest output ==="
echo "$XSS_LINE" | /var/ossec/bin/wazuh-logtest 2>&1
