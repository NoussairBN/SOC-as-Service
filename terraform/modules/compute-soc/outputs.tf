output "wazuh_public_ip"   { value = aws_eip.wazuh.public_ip }
output "wazuh_instance_id" { value = aws_instance.wazuh.id }
output "wazuh_private_ip"  { value = aws_instance.wazuh.private_ip }
