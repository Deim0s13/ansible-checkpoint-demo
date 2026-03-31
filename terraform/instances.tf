# =============================================================================
# instances.tf — EC2 instances and ENIs
#
# Prerequisites:
#   - scripts/import-gaia-ami.sh must be run before applying, so the Gaia AMI
#     ID exists in SSM at var.gaia_ami_ssm_parameter
#   - scripts/bootstrap-state.sh must have been run (backend.tf in place)
# =============================================================================

# ── Key Pair ──────────────────────────────────────────────────────────────────
# Generates a key pair and stores the private key in SSM Parameter Store.
# Access via SSM Session Manager is the primary method — this is a fallback only.

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "demo" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name = var.key_pair_name
  }
}

resource "aws_ssm_parameter" "ssh_private_key" {
  name        = "/checkpoint-demo/ssh-private-key"
  description = "Demo EC2 private key — retrieve with: aws ssm get-parameter --name /checkpoint-demo/ssh-private-key --with-decryption"
  type        = "SecureString"
  value       = tls_private_key.demo.private_key_pem

  tags = {
    Name = "${var.environment}-ssh-private-key"
  }
}

# =============================================================================
# ANSIBLE AUTOMATION PLATFORM SERVER
# =============================================================================

resource "aws_instance" "aap" {
  ami                  = data.aws_ami.rhel9.id
  instance_type        = var.aap_instance_type
  subnet_id            = aws_subnet.mgmt.id
  private_ip           = var.aap_private_ip
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  vpc_security_group_ids = [aws_security_group.mgmt.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100 # AAP installer + collections need space
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Ensure SSM agent is running
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Set hostname
    hostnamectl set-hostname aap.${var.environment}.internal

    # Register with RHSM will be handled by Ansible playbook 01-configure-aap.yml
    # after the trial subscription details are available via Ansible Vault
  EOF
  )

  tags = {
    Name = "${var.environment}-aap-server"
    Role = "ansible-automation-platform"
  }
}

# =============================================================================
# CHECK POINT SECURITY MANAGEMENT SERVER (SMS)
# =============================================================================

resource "aws_instance" "sms" {
  ami                  = data.aws_ssm_parameter.gaia_ami.value
  instance_type        = var.sms_instance_type
  subnet_id            = aws_subnet.mgmt.id
  private_ip           = var.sms_private_ip
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  vpc_security_group_ids = [aws_security_group.mgmt.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  # Gaia first-time configuration via clish
  # Full bootstrap (Management API enablement, admin password) is handled
  # by ansible/playbooks/02-bootstrap-checkpoint.yml
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Retrieve SIC key and admin password from SSM Parameter Store
    SIC_KEY=$(aws ssm get-parameter \
      --name /checkpoint-demo/sic-key \
      --with-decryption \
      --region ${var.region} \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "")

    ADMIN_PASS=$(aws ssm get-parameter \
      --name /checkpoint-demo/sms-admin-password \
      --with-decryption \
      --region ${var.region} \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "")

    # Gaia first-time wizard via clish
    clish -s -c "set user admin password-hash $(echo "$ADMIN_PASS" | openssl passwd -6 -stdin)"
    clish -s -c "set hostname sms"
    clish -s -c "set timezone Australia/Sydney"
    clish -s -c "save config"
  EOF
  )

  tags = {
    Name = "${var.environment}-checkpoint-sms"
    Role = "checkpoint-management-server"
  }
}

# =============================================================================
# CHECK POINT GATEWAY 1
# Three ENIs: mgmt (eth0), external (eth1), internal (eth2)
# Source/dest check disabled on data plane interfaces
# =============================================================================

resource "aws_network_interface" "gw1_mgmt" {
  subnet_id         = aws_subnet.mgmt.id
  private_ips       = [var.gw1_mgmt_ip]
  security_groups   = [aws_security_group.mgmt.id]
  source_dest_check = true # management interface — keep enabled

  tags = {
    Name = "${var.environment}-gw1-mgmt-eni"
  }
}

resource "aws_network_interface" "gw1_external" {
  subnet_id         = aws_subnet.fw_external.id
  private_ips       = [var.gw1_external_ip]
  security_groups   = [aws_security_group.fw_external.id]
  source_dest_check = false # data plane — must be disabled for traffic forwarding

  tags = {
    Name = "${var.environment}-gw1-external-eni"
  }
}

resource "aws_network_interface" "gw1_internal" {
  subnet_id         = aws_subnet.fw_internal.id
  private_ips       = [var.gw1_internal_ip]
  security_groups   = [aws_security_group.fw_internal.id]
  source_dest_check = false # data plane — must be disabled for traffic forwarding

  tags = {
    Name = "${var.environment}-gw1-internal-eni"
  }
}

resource "aws_instance" "gw1" {
  ami                  = data.aws_ssm_parameter.gaia_ami.value
  instance_type        = var.gateway_instance_type
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  # eth0 — management (primary, used for SIC and policy push from SMS)
  network_interface {
    network_interface_id = aws_network_interface.gw1_mgmt.id
    device_index         = 0
  }

  # eth1 — external (untrusted)
  network_interface {
    network_interface_id = aws_network_interface.gw1_external.id
    device_index         = 1
  }

  # eth2 — internal (trusted)
  network_interface {
    network_interface_id = aws_network_interface.gw1_internal.id
    device_index         = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    SIC_KEY=$(aws ssm get-parameter \
      --name /checkpoint-demo/sic-key \
      --with-decryption \
      --region ${var.region} \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "")

    ADMIN_PASS=$(aws ssm get-parameter \
      --name /checkpoint-demo/gw-admin-password \
      --with-decryption \
      --region ${var.region} \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "")

    clish -s -c "set user admin password-hash $(echo "$ADMIN_PASS" | openssl passwd -6 -stdin)"
    clish -s -c "set hostname gw1"
    clish -s -c "set timezone Australia/Sydney"
    clish -s -c "set interface eth1 ipv4-address ${var.gw1_external_ip} mask-length 24"
    clish -s -c "set interface eth2 ipv4-address ${var.gw1_internal_ip} mask-length 24"
    clish -s -c "set sickey $SIC_KEY"
    clish -s -c "save config"
  EOF
  )

  tags = {
    Name = "${var.environment}-checkpoint-gw1"
    Role = "checkpoint-gateway"
  }
}

# =============================================================================
# CHECK POINT GATEWAY 2
# =============================================================================

resource "aws_network_interface" "gw2_mgmt" {
  subnet_id         = aws_subnet.mgmt.id
  private_ips       = [var.gw2_mgmt_ip]
  security_groups   = [aws_security_group.mgmt.id]
  source_dest_check = true

  tags = {
    Name = "${var.environment}-gw2-mgmt-eni"
  }
}

resource "aws_network_interface" "gw2_external" {
  subnet_id         = aws_subnet.fw_external.id
  private_ips       = [var.gw2_external_ip]
  security_groups   = [aws_security_group.fw_external.id]
  source_dest_check = false

  tags = {
    Name = "${var.environment}-gw2-external-eni"
  }
}

resource "aws_network_interface" "gw2_internal" {
  subnet_id         = aws_subnet.fw_internal.id
  private_ips       = [var.gw2_internal_ip]
  security_groups   = [aws_security_group.fw_internal.id]
  source_dest_check = false

  tags = {
    Name = "${var.environment}-gw2-internal-eni"
  }
}

resource "aws_instance" "gw2" {
  ami                  = data.aws_ssm_parameter.gaia_ami.value
  instance_type        = var.gateway_instance_type
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  network_interface {
    network_interface_id = aws_network_interface.gw2_mgmt.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.gw2_external.id
    device_index         = 1
  }

  network_interface {
    network_interface_id = aws_network_interface.gw2_internal.id
    device_index         = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    SIC_KEY=$(aws ssm get-parameter \
      --name /checkpoint-demo/sic-key \
      --with-decryption \
      --region ${var.region} \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "")

    ADMIN_PASS=$(aws ssm get-parameter \
      --name /checkpoint-demo/gw-admin-password \
      --with-decryption \
      --region ${var.region} \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "")

    clish -s -c "set user admin password-hash $(echo "$ADMIN_PASS" | openssl passwd -6 -stdin)"
    clish -s -c "set hostname gw2"
    clish -s -c "set timezone Australia/Sydney"
    clish -s -c "set interface eth1 ipv4-address ${var.gw2_external_ip} mask-length 24"
    clish -s -c "set interface eth2 ipv4-address ${var.gw2_internal_ip} mask-length 24"
    clish -s -c "set sickey $SIC_KEY"
    clish -s -c "save config"
  EOF
  )

  tags = {
    Name = "${var.environment}-checkpoint-gw2"
    Role = "checkpoint-gateway"
  }
}

# =============================================================================
# WINDOWS JUMP SERVER (SmartConsole)
# =============================================================================

resource "aws_instance" "windows" {
  ami                  = data.aws_ami.windows_2022.id
  instance_type        = var.windows_instance_type
  subnet_id            = aws_subnet.access.id
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  vpc_security_group_ids = [aws_security_group.access.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 60
    delete_on_termination = true
    encrypted             = true
  }

  # Enable SSM on Windows and set a known Administrator password stored in SSM
  user_data = base64encode(<<-EOF
    <powershell>
    # Enable SSM agent (pre-installed on Windows Server 2022 AMI)
    Set-Service AmazonSSMAgent -StartupType Automatic
    Start-Service AmazonSSMAgent

    # Retrieve admin password from SSM and set it
    $AdminPass = (Get-SSMParameterValue -Name "/checkpoint-demo/windows-admin-password" -WithDecryption $true).Parameters[0].Value
    net user Administrator $AdminPass

    # Allow RDP (for SSM port-forwarding tunnel)
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    </powershell>
  EOF
  )

  tags = {
    Name = "${var.environment}-windows-jump"
    Role = "smartconsole-host"
  }
}

# =============================================================================
# DEMO WEB SERVER (nginx)
# =============================================================================

resource "aws_instance" "web" {
  ami                  = data.aws_ami.amazon_linux2.id
  instance_type        = var.demo_app_instance_type
  subnet_id            = aws_subnet.fw_internal.id
  private_ip           = var.web_server_ip
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  vpc_security_group_ids = [aws_security_group.web.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx

    # Demo landing page — shows which rules are needed to reach this server
    cat > /usr/share/nginx/html/index.html << 'HTML'
    <!DOCTYPE html>
    <html>
      <head><title>Check Point Demo — Web Server</title></head>
      <body>
        <h1>Web Server Reachable</h1>
        <p>You are seeing this because a Check Point firewall rule permits
           traffic from your source to this server on port 80.</p>
        <p>Server IP: ${var.web_server_ip}</p>
      </body>
    </html>
    HTML

    systemctl enable nginx
    systemctl start nginx
  EOF
  )

  tags = {
    Name = "${var.environment}-web-server"
    Role = "demo-web"
  }
}

# =============================================================================
# DEMO APP SERVER (Flask)
# =============================================================================

resource "aws_instance" "app" {
  ami                  = data.aws_ami.amazon_linux2.id
  instance_type        = var.demo_app_instance_type
  subnet_id            = aws_subnet.fw_internal.id
  private_ip           = var.app_server_ip
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  key_name             = aws_key_pair.demo.key_name

  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 python3-pip
    pip3 install flask

    cat > /opt/app.py << 'PYEOF'
    from flask import Flask, jsonify
    import socket

    app = Flask(__name__)

    @app.route('/')
    def index():
        return jsonify({
            "status": "ok",
            "message": "App server reachable",
            "hostname": socket.gethostname(),
            "service": "checkpoint-demo-app"
        })

    @app.route('/health')
    def health():
        return jsonify({"status": "healthy"})

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=8080)
    PYEOF

    cat > /etc/systemd/system/demo-app.service << 'SVCEOF'
    [Unit]
    Description=Check Point Demo Flask App
    After=network.target

    [Service]
    ExecStart=/usr/bin/python3 /opt/app.py
    Restart=always
    User=root

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    systemctl daemon-reload
    systemctl enable demo-app
    systemctl start demo-app
  EOF
  )

  tags = {
    Name = "${var.environment}-app-server"
    Role = "demo-app"
  }
}
