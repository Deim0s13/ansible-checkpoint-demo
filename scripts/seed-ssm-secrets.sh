#!/usr/bin/env bash
# =============================================================================
# seed-ssm-secrets.sh
#
# Stores demo secrets in AWS SSM Parameter Store (SecureString) before
# terraform apply runs. The EC2 user-data scripts and Ansible playbooks
# retrieve these at runtime — nothing sensitive is stored in Git or in
# the Terraform state.
#
# Run ONCE after bootstrap-state.sh and before terraform apply.
# Safe to re-run — overwrites existing parameters.
#
# Usage:
#   bash scripts/seed-ssm-secrets.sh
# =============================================================================

set -euo pipefail
export AWS_PAGER=""

REGION="ap-southeast-2"

echo ""
echo "================================================="
echo " SSM Secrets Seeding"
echo "================================================="
echo " All values are stored as SecureString (encrypted)"
echo " and never written to disk or Git."
echo ""

put_secret() {
  local name="$1" value="$2" desc="$3"
  aws ssm put-parameter \
    --name "$name" \
    --value "$value" \
    --type "SecureString" \
    --description "$desc" \
    --overwrite \
    --region "$REGION" > /dev/null
  echo "  ✓ $name"
}

# ── SIC Activation Key ────────────────────────────────────────────────────────
# Used by gateway user-data and Ansible playbook 03-establish-sic.yml
# Must be the same value in both places.
read -rsp "Enter SIC activation key (min 8 chars, shown as *): " SIC_KEY
echo ""
[[ ${#SIC_KEY} -ge 8 ]] || { echo "ERROR: SIC key must be at least 8 characters."; exit 1; }
put_secret "/checkpoint-demo/sic-key" "$SIC_KEY" "Check Point SIC activation key — shared between SMS and gateways"

# ── SMS Admin Password ────────────────────────────────────────────────────────
read -rsp "Enter Check Point SMS admin password: " SMS_PASS
echo ""
put_secret "/checkpoint-demo/sms-admin-password" "$SMS_PASS" "Check Point SMS admin user password"

# ── Gateway Admin Password ────────────────────────────────────────────────────
read -rsp "Enter Check Point Gateway admin password (can be same as SMS): " GW_PASS
echo ""
put_secret "/checkpoint-demo/gw-admin-password" "$GW_PASS" "Check Point Gateway admin user password"

# ── Windows Administrator Password ───────────────────────────────────────────
read -rsp "Enter Windows Server Administrator password: " WIN_PASS
echo ""
put_secret "/checkpoint-demo/windows-admin-password" "$WIN_PASS" "Windows jump server Administrator password"

# ── AAP Admin Password ────────────────────────────────────────────────────────
read -rsp "Enter AAP admin password: " AAP_PASS
echo ""
put_secret "/checkpoint-demo/aap-admin-password" "$AAP_PASS" "Ansible Automation Platform admin password"

echo ""
echo "================================================="
echo " ✅  Secrets stored in SSM Parameter Store."
echo ""
echo " To retrieve a secret (e.g. to verify):"
echo "   aws ssm get-parameter --name /checkpoint-demo/sic-key \\"
echo "     --with-decryption --query 'Parameter.Value' --output text"
echo ""
echo " Next step:"
echo "   cd terraform && terraform plan"
echo "================================================="
echo ""
