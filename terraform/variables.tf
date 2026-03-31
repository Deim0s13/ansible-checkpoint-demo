# =============================================================================
# variables.tf
# =============================================================================

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment label applied to all resource Name tags"
  type        = string
  default     = "checkpoint-demo"
}

# ── VPC & Networking ──────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (NAT Gateway only)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "mgmt_subnet_cidr" {
  description = "CIDR for the management subnet (AAP, SMS, GW mgmt ENIs)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "access_subnet_cidr" {
  description = "CIDR for the access subnet (Windows jump server)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "fw_external_subnet_cidr" {
  description = "CIDR for the firewall external (untrusted) subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "fw_internal_subnet_cidr" {
  description = "CIDR for the firewall internal (trusted) subnet"
  type        = string
  default     = "10.0.4.0/24"
}

# ── Instance Types ────────────────────────────────────────────────────────────

variable "aap_instance_type" {
  description = "EC2 instance type for the Ansible Automation Platform server"
  type        = string
  default     = "m5.xlarge"
}

variable "sms_instance_type" {
  description = "EC2 instance type for the Check Point Security Management Server"
  type        = string
  default     = "m5.xlarge"
}

variable "gateway_instance_type" {
  description = "EC2 instance type for Check Point gateways"
  type        = string
  default     = "c5.xlarge"
}

variable "windows_instance_type" {
  description = "EC2 instance type for the Windows SmartConsole jump server"
  type        = string
  default     = "t3.medium"
}

variable "demo_app_instance_type" {
  description = "EC2 instance type for the web and app demo servers"
  type        = string
  default     = "t3.micro"
}

# ── AMI IDs ───────────────────────────────────────────────────────────────────
# Gaia AMI is sourced from SSM Parameter Store (written by import-gaia-ami.sh).
# RHEL 9 and Amazon Linux 2 AMIs are resolved dynamically via data sources in main.tf.
# Windows AMI is also resolved dynamically.

variable "gaia_ami_ssm_parameter" {
  description = "SSM Parameter Store path where import-gaia-ami.sh writes the Gaia AMI ID"
  type        = string
  default     = "/checkpoint-demo/gaia-ami-id"
}

# ── SSH Key Pair ──────────────────────────────────────────────────────────────

variable "key_pair_name" {
  description = "Name of the EC2 key pair to use for instances that support SSH"
  type        = string
  default     = "checkpoint-demo-key"
}

# ── Static IPs (within subnets) ───────────────────────────────────────────────
# Fixing IPs makes the SIC configuration and Ansible inventory deterministic.

variable "aap_private_ip" {
  description = "Fixed private IP for the AAP server (must be within mgmt_subnet_cidr)"
  type        = string
  default     = "10.0.1.10"
}

variable "sms_private_ip" {
  description = "Fixed private IP for the Check Point SMS (must be within mgmt_subnet_cidr)"
  type        = string
  default     = "10.0.1.20"
}

variable "gw1_external_ip" {
  description = "Fixed private IP for GW1 external interface"
  type        = string
  default     = "10.0.3.10"
}

variable "gw1_internal_ip" {
  description = "Fixed private IP for GW1 internal interface"
  type        = string
  default     = "10.0.4.10"
}

variable "gw1_mgmt_ip" {
  description = "Fixed private IP for GW1 management ENI"
  type        = string
  default     = "10.0.1.30"
}

variable "gw2_external_ip" {
  description = "Fixed private IP for GW2 external interface"
  type        = string
  default     = "10.0.3.20"
}

variable "gw2_internal_ip" {
  description = "Fixed private IP for GW2 internal interface"
  type        = string
  default     = "10.0.4.20"
}

variable "gw2_mgmt_ip" {
  description = "Fixed private IP for GW2 management ENI"
  type        = string
  default     = "10.0.1.40"
}

variable "web_server_ip" {
  description = "Fixed private IP for the nginx web server"
  type        = string
  default     = "10.0.4.100"
}

variable "app_server_ip" {
  description = "Fixed private IP for the Flask app server"
  type        = string
  default     = "10.0.4.101"
}
