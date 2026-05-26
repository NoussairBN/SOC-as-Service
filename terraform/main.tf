# ============================================================
# main.tf — Root Module
# ============================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ── Data source: Ubuntu 22.04 LTS AMI (auto-updated) ─────────
data "aws_ami" "ubuntu_22" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu official)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ── Module: Networking ────────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  project_name               = var.project_name
  environment                = var.environment
  vpc_client_cidr            = var.vpc_client_cidr
  vpc_soc_cidr               = var.vpc_soc_cidr
  client_public_subnet_cidr  = var.client_public_subnet_cidr
  client_private_subnet_cidr = var.client_private_subnet_cidr
  soc_public_subnet_cidr     = var.soc_public_subnet_cidr
  my_public_ip               = var.my_public_ip
}

# ── Module: Compute Client VPC ────────────────────────────────
module "compute_client" {
  source = "./modules/compute-client"

  project_name          = var.project_name
  environment           = var.environment
  ami_id                = data.aws_ami.ubuntu_22.id
  instance_type_micro   = var.instance_type_micro
  ssh_public_key        = var.ssh_public_key
  public_subnet_id      = module.networking.client_public_subnet_id
  private_subnet_id     = module.networking.client_private_subnet_id
  sg_bastion_id         = module.networking.sg_bastion_id
  sg_client_private_id  = module.networking.sg_client_private_id
}

# ── Module: Compute SOC VPC ───────────────────────────────────
module "compute_soc" {
  source = "./modules/compute-soc"

  project_name        = var.project_name
  environment         = var.environment
  ami_id              = data.aws_ami.ubuntu_22.id
  instance_type_soc   = var.instance_type_soc
  ssh_public_key      = var.ssh_public_key
  soc_public_subnet_id = module.networking.soc_public_subnet_id
  sg_wazuh_id          = module.networking.sg_wazuh_id
  key_pair_name        = module.compute_client.key_pair_name
}
