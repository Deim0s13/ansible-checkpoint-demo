# =============================================================================
# outputs.tf — Values used by Ansible inventory and deploy.sh
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "mgmt_subnet_id" {
  description = "Management subnet ID"
  value       = aws_subnet.mgmt.id
}

output "access_subnet_id" {
  description = "Access subnet ID"
  value       = aws_subnet.access.id
}

output "fw_external_subnet_id" {
  description = "Firewall external subnet ID"
  value       = aws_subnet.fw_external.id
}

output "fw_internal_subnet_id" {
  description = "Firewall internal subnet ID"
  value       = aws_subnet.fw_internal.id
}

output "aap_private_ip" {
  description = "AAP server private IP (used in Ansible inventory)"
  value       = var.aap_private_ip
}

output "sms_private_ip" {
  description = "Check Point SMS private IP (used in Ansible inventory)"
  value       = var.sms_private_ip
}

output "gw1_mgmt_ip" {
  description = "Check Point GW1 management ENI IP"
  value       = var.gw1_mgmt_ip
}

output "gw2_mgmt_ip" {
  description = "Check Point GW2 management ENI IP"
  value       = var.gw2_mgmt_ip
}

output "web_server_ip" {
  description = "Demo web server private IP"
  value       = var.web_server_ip
}

output "app_server_ip" {
  description = "Demo app server private IP"
  value       = var.app_server_ip
}

output "gaia_ami_id" {
  description = "Gaia AMI ID resolved from SSM (populated by import-gaia-ami.sh)"
  value       = data.aws_ssm_parameter.gaia_ami.value
}

output "rhel9_ami_id" {
  description = "Latest RHEL 9 AMI ID"
  value       = data.aws_ami.rhel9.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP (for allow-listing outbound traffic if needed)"
  value       = aws_eip.nat.public_ip
}
