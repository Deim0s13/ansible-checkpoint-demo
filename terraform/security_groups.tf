# =============================================================================
# security_groups.tf
# =============================================================================

# ── Management Security Group ─────────────────────────────────────────────────
# Applied to: AAP server, Check Point SMS, Gateway management ENIs

resource "aws_security_group" "mgmt" {
  name        = "${var.environment}-mgmt-sg"
  description = "Management tier: AAP, SMS, and gateway management ENIs"
  vpc_id      = aws_vpc.main.id

  # SSM Session Manager — HTTPS to VPC endpoints (or 0.0.0.0/0 for internet-routed SSM)
  egress {
    description = "HTTPS outbound (SSM, package downloads, AAP installer)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound (package downloads)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Check Point Management API — AAP → SMS
  ingress {
    description = "Check Point Management API from AAP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${var.aap_private_ip}/32"]
  }

  # SmartConsole — Windows jump server → SMS
  ingress {
    description = "SmartConsole from Windows jump server"
    from_port   = 19009
    to_port     = 19009
    protocol    = "tcp"
    cidr_blocks = [var.access_subnet_cidr]
  }

  # Check Point SIC — SMS ↔ gateway management ENIs
  ingress {
    description = "SIC between SMS and gateways"
    from_port   = 18191
    to_port     = 18191
    protocol    = "tcp"
    cidr_blocks = [var.mgmt_subnet_cidr]
  }

  egress {
    description = "SIC outbound to gateways"
    from_port   = 18191
    to_port     = 18191
    protocol    = "tcp"
    cidr_blocks = [var.mgmt_subnet_cidr]
  }

  # CPD daemon — used during SIC and policy installation
  ingress {
    description = "CPD daemon from mgmt subnet"
    from_port   = 18192
    to_port     = 18192
    protocol    = "tcp"
    cidr_blocks = [var.mgmt_subnet_cidr]
  }

  egress {
    description = "CPD daemon outbound to gateways"
    from_port   = 18192
    to_port     = 18192
    protocol    = "tcp"
    cidr_blocks = [var.mgmt_subnet_cidr]
  }

  # ICMP — for connectivity testing within mgmt subnet
  ingress {
    description = "ICMP within mgmt subnet"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.mgmt_subnet_cidr]
  }

  egress {
    description = "ICMP outbound within mgmt subnet"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.mgmt_subnet_cidr]
  }

  tags = {
    Name = "${var.environment}-mgmt-sg"
  }
}

# ── Access Security Group ─────────────────────────────────────────────────────
# Applied to: Windows jump server (SmartConsole)

resource "aws_security_group" "access" {
  name        = "${var.environment}-access-sg"
  description = "Access tier: Windows SmartConsole jump server"
  vpc_id      = aws_vpc.main.id

  # RDP is NOT opened here — access is via SSM port-forwarding tunnel only.
  # Egress to SMS for SmartConsole
  egress {
    description = "SmartConsole to SMS"
    from_port   = 19009
    to_port     = 19009
    protocol    = "tcp"
    cidr_blocks = ["${var.sms_private_ip}/32"]
  }

  egress {
    description = "HTTPS outbound (Windows Update, SmartConsole installer)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-access-sg"
  }
}

# ── Firewall External Security Group ─────────────────────────────────────────
# Applied to: Gateway external (eth0) ENIs

resource "aws_security_group" "fw_external" {
  name        = "${var.environment}-fw-external-sg"
  description = "Firewall external interfaces — simulated untrusted traffic"
  vpc_id      = aws_vpc.main.id

  # Allow all inbound on the external interface — the Check Point policy
  # controls what actually passes through. This SG is intentionally permissive
  # because the firewall itself is the enforcement point.
  ingress {
    description = "All traffic — enforced by Check Point policy"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All traffic outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-fw-external-sg"
  }
}

# ── Firewall Internal Security Group ─────────────────────────────────────────
# Applied to: Gateway internal (eth1) ENIs

resource "aws_security_group" "fw_internal" {
  name        = "${var.environment}-fw-internal-sg"
  description = "Firewall internal interfaces — traffic to/from protected subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from protected subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.fw_internal_subnet_cidr]
  }

  egress {
    description = "All traffic to protected subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.fw_internal_subnet_cidr]
  }

  tags = {
    Name = "${var.environment}-fw-internal-sg"
  }
}

# ── Web Server Security Group ─────────────────────────────────────────────────
# Applied to: nginx web server demo instance

resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Demo web server — nginx"
  vpc_id      = aws_vpc.main.id

  # HTTP from gateway internal interfaces only
  ingress {
    description = "HTTP from firewall internal interfaces"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.fw_internal_subnet_cidr]
  }

  # ICMP for connectivity testing
  ingress {
    description = "ICMP for connectivity testing"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.fw_internal_subnet_cidr]
  }

  # Outbound to app server only
  egress {
    description = "HTTP to app server"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${var.app_server_ip}/32"]
  }

  egress {
    description = "HTTPS for package downloads via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package downloads via NAT"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-web-sg"
  }
}

# ── App Server Security Group ─────────────────────────────────────────────────
# Applied to: Flask app server demo instance

resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Demo app server — Flask"
  vpc_id      = aws_vpc.main.id

  # Port 8080 from web server only
  ingress {
    description = "Flask from web server only"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${var.web_server_ip}/32"]
  }

  egress {
    description = "HTTPS for package downloads via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package downloads via NAT"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-app-sg"
  }
}
