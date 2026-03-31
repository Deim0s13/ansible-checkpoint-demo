# =============================================================================
# iam.tf — IAM roles and instance profiles
# =============================================================================

# ── SSM Role (all EC2 instances) ──────────────────────────────────────────────
# Allows SSM Session Manager access — no SSH ports or bastion needed.

resource "aws_iam_role" "ec2_ssm" {
  name        = "${var.environment}-ec2-ssm-role"
  description = "Allows EC2 instances to register with SSM and be accessed via Session Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.environment}-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow instances to read SSM Parameter Store paths under /checkpoint-demo/
resource "aws_iam_role_policy" "ec2_ssm_parameters" {
  name = "${var.environment}-ssm-parameters"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${var.region}:*:parameter/checkpoint-demo/*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.environment}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = {
    Name = "${var.environment}-ec2-ssm-profile"
  }
}

# ── VM Import Role ────────────────────────────────────────────────────────────
# Required by AWS VM Import/Export to import the Gaia OVA.
# Must be named exactly "vmimport" — this is an AWS requirement.

resource "aws_iam_role" "vmimport" {
  name        = "vmimport"
  description = "Required by AWS VM Import/Export for importing OVA images"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vmie.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "vmimport"
        }
      }
    }]
  })

  tags = {
    Name = "vmimport"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "vmimport" {
  name = "vmimport-policy"
  role = aws_iam_role.vmimport.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetBucketAcl"
        ]
        Resource = [
          "arn:aws:s3:::checkpoint-demo-tfstate-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::checkpoint-demo-tfstate-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:ModifySnapshotAttribute",
          "ec2:CopySnapshot",
          "ec2:RegisterImage",
          "ec2:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}
