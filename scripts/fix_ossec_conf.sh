#!/bin/bash
# Write a clean ossec.conf for the dvwa-apache agent
cat > /var/ossec/etc/ossec.conf << 'OSSECEOF'
<ossec_config>

  <!-- ═══════════════════════════════════════════════════════
       Agent Configuration — dvwa-apache
       Manager : 10.1.1.133
       ═══════════════════════════════════════════════════════ -->

  <client>
    <server>
      <address>10.1.1.133</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <crypto_method>aes</crypto_method>
    <notify_time>10</notify_time>
    <time-reconnect>60</time-reconnect>
    <auto_restart>yes</auto_restart>
  </client>

  <!-- File Integrity Monitoring -->
  <syscheck>
    <frequency>300</frequency>
    <scan_on_start>yes</scan_on_start>
    <alert_new_files>yes</alert_new_files>
    <directories check_all="yes" realtime="yes">/etc</directories>
    <directories check_all="yes" realtime="yes">/usr/bin,/usr/sbin,/bin,/sbin</directories>
    <directories check_all="yes" realtime="yes">/var/www</directories>
    <directories check_all="yes">/home</directories>
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
  </syscheck>

  <!-- Log collection -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <!-- DVWA Apache access log forwarded from Docker container -->
  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/dvwa-access.log</location>
  </localfile>

  <!-- Active Response -->
  <active-response>
    <disabled>no</disabled>
    <ca_store>/var/ossec/etc/wpk_root.pem</ca_store>
  </active-response>

</ossec_config>
OSSECEOF

chown root:wazuh /var/ossec/etc/ossec.conf
chmod 640 /var/ossec/etc/ossec.conf
echo "ossec.conf written."

# Test config
echo "=== Testing config ==="
/var/ossec/bin/wazuh-agentd -t
echo "Config OK"

# Restart agent
echo "=== Starting wazuh-agent ==="
/var/ossec/bin/wazuh-control start
sleep 5
echo "=== Agent logs ==="
tail -10 /var/ossec/logs/ossec.log
