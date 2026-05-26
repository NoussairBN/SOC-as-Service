# ============================================================
# modules/networking/main.tf
# VPCs, Subnets, IGWs, VPC Peering, Route Tables, Security Groups
# ============================================================

# ── VPC Client ───────────────────────────────────────────────
resource "aws_vpc" "client" {
  cidr_block           = var.vpc_client_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-client"
    Role = "client"
  }
}

# ── VPC SOC ──────────────────────────────────────────────────
resource "aws_vpc" "soc" {
  cidr_block           = var.vpc_soc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-soc"
    Role = "soc"
  }
}

# ── Internet Gateway — Client VPC ─────────────────────────────
resource "aws_internet_gateway" "client" {
  vpc_id = aws_vpc.client.id

  tags = {
    Name = "${var.project_name}-igw-client"
  }
}

# ── Internet Gateway — SOC VPC ────────────────────────────────
resource "aws_internet_gateway" "soc" {
  vpc_id = aws_vpc.soc.id

  tags = {
    Name = "${var.project_name}-igw-soc"
  }
}

# ── Subnet Public — Client VPC (Bastion) ─────────────────────
resource "aws_subnet" "client_public" {
  vpc_id                  = aws_vpc.client.id
  cidr_block              = var.client_public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false # On gère les EIP manuellement

  tags = {
    Name = "${var.project_name}-subnet-client-public"
    Tier = "public"
  }
}

# ── Subnet Private — Client VPC (DVWA + Metasploitable) ──────
resource "aws_subnet" "client_private" {
  vpc_id            = aws_vpc.client.id
  cidr_block        = var.client_private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-subnet-client-private"
    Tier = "private"
  }
}

# ── Subnet Public — SOC VPC (Wazuh) ──────────────────────────
resource "aws_subnet" "soc_public" {
  vpc_id                  = aws_vpc.soc.id
  cidr_block              = var.soc_public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-soc-public"
    Tier = "public"
  }
}

# ── Route Table — Client Public ───────────────────────────────
resource "aws_route_table" "client_public" {
  vpc_id = aws_vpc.client.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.client.id
  }

  # Route vers le VPC SOC via le peering
  route {
    cidr_block                = var.vpc_soc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.client_to_soc.id
  }

  tags = {
    Name = "${var.project_name}-rt-client-public"
  }
}

resource "aws_route_table_association" "client_public" {
  subnet_id      = aws_subnet.client_public.id
  route_table_id = aws_route_table.client_public.id
}

# ── Elastic IP pour NAT Gateway ─────────────────────────────
resource "aws_eip" "nat_client" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip-nat-client"
  }
}

# ── NAT Gateway — Client VPC (dans le subnet public) ─────────
# Permet aux instances privées (DVWA, Meta) d'accéder à internet
resource "aws_nat_gateway" "client" {
  allocation_id = aws_eip.nat_client.id
  subnet_id     = aws_subnet.client_public.id

  tags = {
    Name = "${var.project_name}-nat-client"
  }

  depends_on = [aws_internet_gateway.client]
}

# ── Route Table — Client Private ──────────────────────────────
resource "aws_route_table" "client_private" {
  vpc_id = aws_vpc.client.id

  # Internet via NAT Gateway (pour apt update, Docker pull, etc.)
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.client.id
  }

  # Route vers le VPC SOC via le peering (pour les agents Wazuh)
  route {
    cidr_block                = var.vpc_soc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.client_to_soc.id
  }

  tags = {
    Name = "${var.project_name}-rt-client-private"
  }
}

resource "aws_route_table_association" "client_private" {
  subnet_id      = aws_subnet.client_private.id
  route_table_id = aws_route_table.client_private.id
}

# ── Route Table — SOC Public ──────────────────────────────────
resource "aws_route_table" "soc_public" {
  vpc_id = aws_vpc.soc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.soc.id
  }

  # Route vers le VPC Client via le peering
  route {
    cidr_block                = var.vpc_client_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.client_to_soc.id
  }

  tags = {
    Name = "${var.project_name}-rt-soc-public"
  }
}

resource "aws_route_table_association" "soc_public" {
  subnet_id      = aws_subnet.soc_public.id
  route_table_id = aws_route_table.soc_public.id
}

# ── VPC Peering — Client <-> SOC ──────────────────────────────
resource "aws_vpc_peering_connection" "client_to_soc" {
  vpc_id      = aws_vpc.client.id
  peer_vpc_id = aws_vpc.soc.id
  auto_accept = true # Meme compte AWS = auto-accept

  tags = {
    Name = "${var.project_name}-peering-client-soc"
  }
}

# ============================================================
# Security Groups
# ============================================================

# ── SG Bastion ───────────────────────────────────────────────
# SSH uniquement depuis ton IP publique
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-sg-bastion"
  description = "Bastion host - SSH restricted to admin IP"
  vpc_id      = aws_vpc.client.id

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_public_ip]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-bastion"
  }
}

# ── SG Client Private (DVWA + Metasploitable) ────────────────
resource "aws_security_group" "client_private" {
  name        = "${var.project_name}-sg-client-private"
  description = "Private client instances - SSH via bastion + Wazuh agent ports"
  vpc_id      = aws_vpc.client.id

  # SSH depuis le bastion uniquement
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # HTTP/HTTPS pour DVWA (depuis le bastion seulement pour les tests)
  ingress {
    description     = "HTTP for DVWA from Bastion"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Wazuh agent communication vers le manager (outbound uniquement)
  egress {
    description = "Allow all outbound (Wazuh agents + updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-client-private"
  }
}

# ── SG Wazuh Server ──────────────────────────────────────────
resource "aws_security_group" "wazuh" {
  name        = "${var.project_name}-sg-wazuh"
  description = "Wazuh server - Dashboard + Agent ports + SSH from bastion"
  vpc_id      = aws_vpc.soc.id

  # SSH depuis le bastion (via VPC Peering)
  ingress {
    description = "SSH from Bastion via VPC Peering"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.client_public_subnet_cidr]
  }

  # Dashboard Wazuh (HTTPS) - depuis ton IP pour la demo
  ingress {
    description = "Wazuh Dashboard HTTPS from admin IP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.my_public_ip]
  }

  # Wazuh agent registration port (depuis le VPC Client)
  ingress {
    description = "Wazuh agent registration from Client VPC"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = [var.vpc_client_cidr]
  }

  # Wazuh agent event forwarding (depuis le VPC Client)
  ingress {
    description = "Wazuh agent events from Client VPC"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = [var.vpc_client_cidr]
  }

  # Wazuh agent event forwarding UDP (depuis le VPC Client)
  ingress {
    description = "Wazuh agent events UDP from Client VPC"
    from_port   = 1514
    to_port     = 1514
    protocol    = "udp"
    cidr_blocks = [var.vpc_client_cidr]
  }

  # Wazuh Indexer API (interne uniquement)
  ingress {
    description = "Wazuh Indexer API (internal)"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [var.soc_public_subnet_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-wazuh"
  }
}
