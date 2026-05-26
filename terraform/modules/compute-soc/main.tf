# ============================================================
# modules/compute-soc/main.tf
# Wazuh Server dans le VPC SOC
# ============================================================

# ── Wazuh Server ─────────────────────────────────────────────
resource "aws_instance" "wazuh" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_soc
  subnet_id              = var.soc_public_subnet_id
  vpc_security_group_ids = [var.sg_wazuh_id]
  key_name               = var.key_pair_name

  # Wazuh requiert au minimum 4 GB de RAM
  # c7i-flex.large : 2 vCPU, 4 GB RAM — suffisant pour notre stack
  root_block_device {
    volume_size           = 50  # Wazuh indexer nécessite de l'espace pour les logs
    volume_type           = "gp3"
    iops                  = 3000
    delete_on_termination = true
  }

  # user_data : préparation système avant Ansible
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Mise a jour systeme
    apt-get update -y
    apt-get upgrade -y

    # Dependances necessaires pour Wazuh
    apt-get install -y curl gnupg apt-transport-https lsb-release

    # Optimisation kernel pour Wazuh Indexer (OpenSearch)
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -p

    # Augmenter les limites fichiers pour OpenSearch
    echo "* soft nofile 65536" >> /etc/security/limits.conf
    echo "* hard nofile 65536" >> /etc/security/limits.conf

    echo "Wazuh instance ready for Ansible" > /tmp/wazuh_ready.txt
  EOF
  )

  tags = {
    Name    = "${var.project_name}-wazuh-server"
    Role    = "wazuh_server"
    VPC     = "soc"
    Project = var.project_name
  }
}

# ── Elastic IP — Wazuh ────────────────────────────────────────
resource "aws_eip" "wazuh" {
  instance = aws_instance.wazuh.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip-wazuh"
  }
}
