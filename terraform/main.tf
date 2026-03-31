# =============================================================================
# main.tf — Provider, VPC, subnets, routing, NAT Gateway
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "ansible-checkpoint-demo"
    }
  }
}

# ── AMI Data Sources ──────────────────────────────────────────────────────────

# RHEL 9 — for the AAP server
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat's official AWS account ID

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Amazon Linux 2 — for web and app demo servers
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Windows Server 2022 — for the SmartConsole jump server
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Gaia AMI — imported via scripts/import-gaia-ami.sh and stored in SSM
data "aws_ssm_parameter" "gaia_ami" {
  name = var.gaia_ami_ssm_parameter
}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-igw"
  }
}

# ── Subnets ───────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false # NAT GW only — no instances here

  tags = {
    Name = "${var.environment}-public-subnet"
  }
}

resource "aws_subnet" "mgmt" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.mgmt_subnet_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.environment}-mgmt-subnet"
  }
}

resource "aws_subnet" "access" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.access_subnet_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.environment}-access-subnet"
  }
}

resource "aws_subnet" "fw_external" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.fw_external_subnet_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.environment}-fw-external-subnet"
  }
}

resource "aws_subnet" "fw_internal" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.fw_internal_subnet_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.environment}-fw-internal-subnet"
  }
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.environment}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.environment}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── Route Tables ──────────────────────────────────────────────────────────────

# Public route table — routes to IGW (used by NAT Gateway subnet)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table — shared by mgmt, access, fw-external, fw-internal
# All outbound traffic goes via NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "mgmt" {
  subnet_id      = aws_subnet.mgmt.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "access" {
  subnet_id      = aws_subnet.access.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "fw_external" {
  subnet_id      = aws_subnet.fw_external.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "fw_internal" {
  subnet_id      = aws_subnet.fw_internal.id
  route_table_id = aws_route_table.private.id
}
