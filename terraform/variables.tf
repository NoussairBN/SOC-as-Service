# ============================================================
# variables.tf — Root Module
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming"
  type        = string
  default     = "pfs-soc"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# ── Networking ───────────────────────────────────────────────

variable "vpc_client_cidr" {
  description = "CIDR block for the Client VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_soc_cidr" {
  description = "CIDR block for the SOC VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "client_public_subnet_cidr" {
  description = "CIDR for client public subnet (Bastion)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "client_private_subnet_cidr" {
  description = "CIDR for client private subnet (DVWA, Metasploitable)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "soc_public_subnet_cidr" {
  description = "CIDR for SOC public subnet (Wazuh)"
  type        = string
  default     = "10.1.1.0/24"
}

# ── Compute ──────────────────────────────────────────────────

variable "instance_type_micro" {
  description = "Instance type for lightweight workloads (Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_soc" {
  description = "Instance type for the Wazuh SOC server"
  type        = string
  default     = "c7i-flex.large"
}

variable "ssh_public_key" {
  description = "SSH public key content for EC2 access"
  type        = string
  sensitive   = true
}

variable "my_public_ip" {
  description = "Your public IP to restrict SSH access to Bastion (format: x.x.x.x/32)"
  type        = string
  # Get your IP: curl ifconfig.me
}
