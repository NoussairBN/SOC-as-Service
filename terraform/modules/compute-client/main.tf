# ============================================================
# modules/compute-client/main.tf
# Bastion + DVWA + Metasploitable dans le VPC Client
# ============================================================

# ── SSH Key Pair ─────────────────────────────────────────────
resource "aws_key_pair" "pfs_soc" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.project_name}-key"
  }
}

# ── Bastion Host ─────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_micro
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.sg_bastion_id]
  key_name               = aws_key_pair.pfs_soc.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nmap hydra netcat-openbsd curl
    echo "Bastion ready" > /tmp/bastion_ready.txt
  EOF
  )

  tags = {
    Name    = "${var.project_name}-bastion"
    Role    = "bastion"
    VPC     = "client"
    Project = var.project_name
  }
}

# ── Elastic IP — Bastion ──────────────────────────────────────
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip-bastion"
  }
}

# ── DVWA Instance ─────────────────────────────────────────────
resource "aws_instance" "dvwa" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_micro
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.sg_client_private_id]
  key_name               = aws_key_pair.pfs_soc.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # DVWA sera installé par Ansible
  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose curl
    systemctl enable docker
    systemctl start docker
    echo "DVWA instance ready for Ansible" > /tmp/dvwa_ready.txt
  EOF
  )

  tags = {
    Name    = "${var.project_name}-dvwa"
    Role    = "dvwa"
    VPC     = "client"
    Project = var.project_name
  }
}

# ── Metasploitable Instance ───────────────────────────────────
resource "aws_instance" "metasploitable" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_micro
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.sg_client_private_id]
  key_name               = aws_key_pair.pfs_soc.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Metasploitable sera configuré par Ansible (services vulnérables activés)
  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y openssh-server vsftpd curl
    # Affaiblir la config SSH pour la démo brute-force
    sed -i 's/^#MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    echo "Metasploitable instance ready for Ansible" > /tmp/meta_ready.txt
  EOF
  )

  tags = {
    Name    = "${var.project_name}-metasploitable"
    Role    = "metasploitable"
    VPC     = "client"
    Project = var.project_name
  }
}
