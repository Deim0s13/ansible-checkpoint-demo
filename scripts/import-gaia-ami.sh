#!/usr/bin/env bash
# =============================================================================
# import-gaia-ami.sh
#
# Imports a Check Point Gaia OVA into AWS as a private AMI using
# VM Import/Export, then stores the resulting AMI ID in SSM Parameter Store.
#
# Prerequisites:
#   - Terraform must have been applied at least once (creates the vmimport IAM
#     role and the S3 bucket for Terraform state; we reuse that bucket for the
#     OVA upload, or you can set IMPORT_BUCKET manually below).
#   - AWS CLI configured with sufficient permissions (ec2:ImportImage,
#     ec2:DescribeImportImageTasks, s3:PutObject, ssm:PutParameter).
#   - The Gaia R81.20 OVA downloaded from Check Point UserCenter.
#
# Usage:
#   bash scripts/import-gaia-ami.sh /path/to/Check_Point_Gaia_R81.20.ova
#
# The AMI ID is written to SSM at /checkpoint-demo/gaia-ami-id.
# After this script completes, export the variable and re-run terraform apply:
#
#   export TF_VAR_gaia_ami_id=$(aws ssm get-parameter \
#     --name /checkpoint-demo/gaia-ami-id --with-decryption \
#     --query 'Parameter.Value' --output text)
#   cd terraform && terraform apply
# =============================================================================

set -euo pipefail
export AWS_PAGER=""

# ── Configuration ─────────────────────────────────────────────────────────────

REGION="ap-southeast-2"
SSM_PARAM="/checkpoint-demo/gaia-ami-id"

# S3 bucket for the OVA upload. Defaults to the Terraform state bucket
# (already exists and has versioning/encryption). Override if needed.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
IMPORT_BUCKET="checkpoint-demo-tfstate-${ACCOUNT_ID}"
S3_KEY_PREFIX="gaia-ova-import"

# ── Argument check ────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/Check_Point_Gaia_R81.20.ova"
  exit 1
fi

OVA_PATH="$1"

if [[ ! -f "$OVA_PATH" ]]; then
  echo "ERROR: OVA file not found: $OVA_PATH"
  exit 1
fi

OVA_FILENAME=$(basename "$OVA_PATH")

echo ""
echo "================================================="
echo " Check Point Gaia AMI Import"
echo "================================================="
echo " OVA       : $OVA_PATH"
echo " Bucket    : s3://${IMPORT_BUCKET}/${S3_KEY_PREFIX}/${OVA_FILENAME}"
echo " Region    : $REGION"
echo " SSM param : $SSM_PARAM"
echo ""

# ── Upload OVA to S3 ──────────────────────────────────────────────────────────

echo "Step 1/4 - Uploading OVA to S3 (this may take several minutes)..."
aws s3 cp "$OVA_PATH" \
  "s3://${IMPORT_BUCKET}/${S3_KEY_PREFIX}/${OVA_FILENAME}" \
  --region "$REGION" \
  --no-progress

echo "  Upload complete."
echo ""

# ── Start import-image task ───────────────────────────────────────────────────

echo "Step 2/4 - Starting import-image task..."

IMPORT_TASK_ID=$(aws ec2 import-image \
  --region "$REGION" \
  --architecture x86_64 \
  --platform Linux \
  --license-type BYOL \
  --description "Check Point Gaia R81.20 - imported $(date +%Y-%m-%d)" \
  --disk-containers "Format=OVA,UserBucket={S3Bucket=${IMPORT_BUCKET},S3Key=${S3_KEY_PREFIX}/${OVA_FILENAME}}" \
  --query 'ImportTaskId' \
  --output text)

echo "  Import task ID: $IMPORT_TASK_ID"
echo ""

# ── Poll until complete ───────────────────────────────────────────────────────

echo "Step 3/4 - Waiting for import to complete (typically 15-30 minutes)..."
echo "  Progress will be shown every 60 seconds."
echo ""

POLL_INTERVAL=60
ELAPSED=0

while true; do
  TASK_OUTPUT=$(aws ec2 describe-import-image-tasks \
    --region "$REGION" \
    --import-task-ids "$IMPORT_TASK_ID" \
    --query 'ImportImageTasks[0]' \
    --output json)

  STATUS=$(echo "$TASK_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Status'])")
  PROGRESS=$(echo "$TASK_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Progress','?'))")
  STATUS_MSG=$(echo "$TASK_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('StatusMessage',''))")

  printf "  [%3dm elapsed] Status: %-12s Progress: %-4s %s\n" \
    $((ELAPSED / 60)) "$STATUS" "$PROGRESS" "$STATUS_MSG"

  if [[ "$STATUS" == "completed" ]]; then
    AMI_ID=$(echo "$TASK_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['ImageId'])")
    echo ""
    echo "  Import completed. AMI ID: $AMI_ID"
    break
  fi

  if [[ "$STATUS" == "deleted" || "$STATUS" == "deleting" ]]; then
    echo ""
    echo "ERROR: Import task failed. Status: $STATUS"
    echo "       StatusMessage: $STATUS_MSG"
    echo ""
    echo "Common causes:"
    echo "  - vmimport IAM role missing or misconfigured (run: terraform apply first)"
    echo "  - Unsupported OVA format (ensure you downloaded the .ova, not .iso)"
    echo "  - S3 bucket permissions"
    exit 1
  fi

  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# ── Store AMI ID in SSM ───────────────────────────────────────────────────────

echo ""
echo "Step 4/4 - Storing AMI ID in SSM Parameter Store..."

aws ssm put-parameter \
  --region "$REGION" \
  --name "$SSM_PARAM" \
  --value "$AMI_ID" \
  --type "SecureString" \
  --description "Check Point Gaia R81.20 AMI ID - imported $(date +%Y-%m-%d)" \
  --overwrite > /dev/null

echo "  Stored: $SSM_PARAM = $AMI_ID"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "================================================="
echo " Import complete."
echo ""
echo " AMI ID : $AMI_ID"
echo " SSM    : $SSM_PARAM"
echo ""
echo " Next steps:"
echo ""
echo "   export TF_VAR_gaia_ami_id=\$(aws ssm get-parameter \\"
echo "     --name $SSM_PARAM --with-decryption \\"
echo "     --query 'Parameter.Value' --output text)"
echo ""
echo "   cd terraform && terraform apply"
echo "================================================="
echo ""
