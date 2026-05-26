# ============================================================
# outputs.tf — Root Module
# ============================================================

output "bastion_public_ip" {
  description = "Public IP of the Bastion host"
  value       = module.compute_client.bastion_public_ip
}

output "wazuh_public_ip" {
  description = "Public IP of the Wazuh server"
  value       = module.compute_soc.wazuh_public_ip
}

output "wazuh_dashboard_url" {
  description = "Wazuh Dashboard URL"
  value       = "https://${module.compute_soc.wazuh_public_ip}"
}

output "dvwa_private_ip" {
  description = "Private IP of the DVWA instance"
  value       = module.compute_client.dvwa_private_ip
}

output "metasploitable_private_ip" {
  description = "Private IP of the Metasploitable instance"
  value       = module.compute_client.metasploitable_private_ip
}

output "ssh_bastion_command" {
  description = "SSH command to connect to the Bastion"
  value       = "ssh -i ~/.ssh/pfs-soc-key ubuntu@${module.compute_client.bastion_public_ip}"
}

output "ssh_wazuh_via_bastion" {
  description = "SSH command to connect to Wazuh via Bastion jump"
  value       = "ssh -i ~/.ssh/pfs-soc-key -J ubuntu@${module.compute_client.bastion_public_ip} ubuntu@${module.compute_soc.wazuh_public_ip}"
}

output "ami_id_used" {
  description = "Ubuntu 22.04 AMI ID used for all instances"
  value       = data.aws_ami.ubuntu_22.id
}

output "vpc_client_id" {
  description = "ID of the Client VPC"
  value       = module.networking.vpc_client_id
}

output "vpc_soc_id" {
  description = "ID of the SOC VPC"
  value       = module.networking.vpc_soc_id
}
