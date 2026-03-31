#!/usr/bin/env bash
# =============================================================================
# create-github-backlog.sh
#
# Creates GitHub labels, milestones, and issues for the Ansible + Check Point
# demo project. Run once from your local machine after pushing the repo.
#
# Prerequisites: gh CLI installed and authenticated (gh auth status)
# Usage: bash scripts/create-github-backlog.sh
# =============================================================================

set -euo pipefail

REPO="Deim0s13/ansible-checkpoint-demo"

echo ""
echo "================================================="
echo " Ansible + Check Point Demo — GitHub Backlog Setup"
echo "================================================="
echo " Repo: https://github.com/$REPO"
echo ""

# ─── Confirm before proceeding ───────────────────────────────────────────────
read -rp "This will create labels, milestones, and issues in $REPO. Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# =============================================================================
# LABELS
# =============================================================================
echo ""
echo "🏷️  Creating labels..."

create_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" \
    --color "$color" \
    --description "$desc" \
    --repo "$REPO" \
    --force 2>/dev/null && echo "  ✓ $name" || echo "  ~ $name (skipped)"
}

create_label "terraform"    "0075ca" "Terraform infrastructure code"
create_label "ansible"      "e4e669" "Ansible playbooks and roles"
create_label "checkpoint"   "d93f0b" "Check Point firewall configuration"
create_label "aap"          "7057ff" "Ansible Automation Platform"
create_label "aws"          "f9a825" "AWS infrastructure and services"
create_label "demo"         "0e8a16" "Demo scenarios and content"
create_label "networking"   "1d76db" "Network design and connectivity"
create_label "security"     "b60205" "Security configuration and secrets"
create_label "algosec"      "006b75" "AlgoSec integration (Phase 5)"
create_label "servicenow"   "0052cc" "ServiceNow integration (Phase 6)"
create_label "documentation" "cccccc" "Documentation and planning"

# =============================================================================
# MILESTONES
# =============================================================================
echo ""
echo "🪨  Creating milestones..."

create_milestone() {
  local title="$1" desc="$2"
  number=$(gh api "repos/$REPO/milestones" \
    --method POST \
    -f title="$title" \
    -f description="$desc" \
    -f state="open" \
    --jq '.number' 2>/dev/null || echo "")
  if [[ -n "$number" ]]; then
    echo "  ✓ $title (milestone #$number)"
    echo "$number"
  else
    # Already exists — look it up
    number=$(gh api "repos/$REPO/milestones" --jq ".[] | select(.title==\"$title\") | .number" 2>/dev/null || echo "0")
    echo "  ~ $title exists (milestone #$number)"
    echo "$number"
  fi
}

M0=$(create_milestone "Phase 0: Prerequisites" \
  "AWS account, IAM permissions, Gaia OVA import, Check Point eval licence, AAP installer bundle, Terraform state bootstrap")
M0="${M0##*$'\n'}"

M1=$(create_milestone "Phase 1: AWS Infrastructure" \
  "VPC, subnets, security groups, EC2 instances, ENIs, SSM access, NAT gateway — terraform apply produces a running environment")
M1="${M1##*$'\n'}"

M2=$(create_milestone "Phase 2: Check Point Bootstrap" \
  "Gaia first-time wizard via user-data, SIC establishment, Management API enabled, SmartConsole connected, initial policy installed")
M2="${M2##*$'\n'}"

M3=$(create_milestone "Phase 3: AAP Configuration" \
  "AAP installed, check_point.mgmt collection deployed, inventory and credentials configured, demo job templates with Survey prompts created")
M3="${M3##*$'\n'}"

M4=$(create_milestone "Phase 4: Demo Hardening" \
  "All five scenarios tested end-to-end, reset playbook validated, deploy/teardown tested from clean account, demo run sheet written")
M4="${M4##*$'\n'}"

M5=$(create_milestone "Phase 5: AlgoSec Integration" \
  "AlgoSec AFA deployed, integrated with Check Point SMS, risk analysis gate added to Ansible playbooks")
M5="${M5##*$'\n'}"

M6=$(create_milestone "Phase 6: ServiceNow Self-Service" \
  "ServiceNow PDI configured, firewall rule request catalogue item built, AAP triggered via webhook on approval")
M6="${M6##*$'\n'}"

# =============================================================================
# ISSUES
# =============================================================================
echo ""
echo "📋  Creating issues..."

create_issue() {
  local title="$1" body="$2" milestone="$3"
  shift 3
  local labels=("$@")
  local label_args=()
  for l in "${labels[@]}"; do
    label_args+=(--label "$l")
  done
  gh issue create \
    --repo "$REPO" \
    --title "$title" \
    --body "$body" \
    --milestone "$milestone" \
    "${label_args[@]}" \
    --assignee "@me" \
    2>/dev/null && echo "  ✓ $title" || echo "  ~ $title (may already exist)"
}

# ── Phase 0: Prerequisites ────────────────────────────────────────────────────
echo ""
echo "  Phase 0: Prerequisites"

create_issue \
  "Create IAM user/role with minimum required Terraform permissions" \
  "Create a dedicated IAM identity for Terraform with the minimum required permissions.

Document the policy in \`terraform/iam-bootstrap-policy.json\` covering:
- EC2 (full)
- VPC (full)
- IAM (limited — create/attach roles and instance profiles only)
- SSM Parameter Store (read/write on \`/demo/*\` path)
- Secrets Manager (read/write on demo secrets)
- S3 (full on the state bucket)
- DynamoDB (full on the lock table)
- VM Import/Export (\`ec2:ImportImage\`, \`ec2:DescribeImportImageTasks\`)

Acceptance criteria: \`terraform plan\` runs without permissions errors." \
  "$M0" "aws" "terraform" "security"

create_issue \
  "Bootstrap Terraform remote state (S3 + DynamoDB)" \
  "Run \`scripts/bootstrap-state.sh\` to create the S3 bucket and DynamoDB table required for Terraform remote state.

These resources must exist before \`terraform init\` can be run with the S3 backend configured in \`terraform/backend.tf\`.

Acceptance criteria:
- S3 bucket created with versioning enabled
- DynamoDB table created with \`LockID\` as the partition key
- \`terraform init\` completes without error" \
  "$M0" "aws" "terraform"

create_issue \
  "Download Check Point Gaia R81.20 OVA from UserCenter" \
  "Download the Check Point Gaia R81.20 OVA from the [Check Point UserCenter](https://supportcenter.checkpoint.com).

A UserCenter account is required. Download the VMware-format OVA as this is the format accepted by AWS VM Import/Export.

Store the OVA locally — do **not** commit it to this repo (it is in \`.gitignore\` due to size)." \
  "$M0" "checkpoint" "aws"

create_issue \
  "Import Gaia OVA to AWS and create custom AMI" \
  "Run \`scripts/import-gaia-ami.sh\` to import the Check Point Gaia R81.20 OVA into AWS and create a custom AMI.

The script:
1. Uploads the OVA to the Terraform state S3 bucket under \`images/\`
2. Runs \`aws ec2 import-image\`
3. Polls until the import completes (~15-30 minutes)
4. Writes the resulting AMI ID to SSM Parameter Store at \`/demo/checkpoint/ami_id\`

Terraform resolves the AMI ID from SSM automatically — it is never hard-coded.

Acceptance criteria: AMI appears in EC2 console and SSM parameter is set." \
  "$M0" "checkpoint" "aws"

create_issue \
  "Obtain Check Point 90-day evaluation licence" \
  "Request a 90-day evaluation licence through your Check Point partner or sales contact.

The licence is applied to the SMS during bootstrap and pushed to the gateways — it is not tied to the AMI. Running Gaia as a BYOL instance without a valid licence will result in limited functionality after a grace period.

Acceptance criteria: Licence file or activation string received and stored ready for bootstrap." \
  "$M0" "checkpoint"

create_issue \
  "Download AAP installer bundle and upload to S3" \
  "Download the Red Hat Ansible Automation Platform installer bundle from the [Red Hat Customer Portal](https://access.redhat.com).

A Red Hat account with an active trial subscription is required.

Upload the bundle to the Terraform state S3 bucket at a known path (e.g. \`aap/ansible-automation-platform-setup-bundle-latest.tar.gz\`). The AAP bootstrap playbook retrieves it from S3 during deployment.

Do **not** commit the bundle to this repo.

Acceptance criteria: Bundle is accessible at the expected S3 path and the trial subscription is active." \
  "$M0" "aap" "aws"

# ── Phase 1: AWS Infrastructure ───────────────────────────────────────────────
echo ""
echo "  Phase 1: AWS Infrastructure"

create_issue \
  "Create VPC, subnets, and route tables" \
  "Implement \`terraform/main.tf\` to create:

- VPC: \`10.0.0.0/16\`
- \`public-subnet\`: \`10.0.0.0/24\`
- \`mgmt-subnet\`: \`10.0.1.0/24\`
- \`access-subnet\`: \`10.0.2.0/24\`
- \`fw-external-subnet\`: \`10.0.3.0/24\`
- \`fw-internal-subnet\`: \`10.0.4.0/24\`
- Internet Gateway attached to VPC
- NAT Gateway in public-subnet
- Route tables for each subnet

Acceptance criteria: \`terraform apply\` creates all networking resources without error." \
  "$M1" "terraform" "networking" "aws"

create_issue \
  "Create security groups for all tiers" \
  "Define security groups in \`terraform/main.tf\` for each tier:

- **mgmt-sg**: allows SSM endpoints, SMS API (:443) from AAP, SmartConsole (:19009) from access-subnet, SIC (:18211) from mgmt-subnet
- **access-sg**: allows RDP (:3389) via SSM tunnel only
- **fw-external-sg**: allows traffic to flow through to gateways
- **fw-internal-sg**: allows traffic from gateway internal interfaces to web/app servers
- **app-sg**: allows :8080 from web server only

Acceptance criteria: All SGs created, no 0.0.0.0/0 ingress rules on sensitive ports." \
  "$M1" "terraform" "networking" "security" "aws"

create_issue \
  "Create IAM roles and instance profiles" \
  "Implement \`terraform/iam.tf\` to create:

- **vmimport role**: required for VM Import/Export (must be named exactly \`vmimport\`)
- **ec2-ssm-role**: attached to all EC2 instances to enable SSM Session Manager access
- **aap-role**: allows AAP server to read from SSM Parameter Store (\`/demo/*\`)
- Instance profiles for each role

Acceptance criteria: All roles created, instances can be reached via \`aws ssm start-session\`." \
  "$M1" "terraform" "aws" "security"

create_issue \
  "Define EC2 instances in Terraform" \
  "Implement \`terraform/instances.tf\` for all instances:

| Instance | AMI | Size |
|----------|-----|------|
| AAP Server | RHEL 9 (from SSM) | m5.xlarge |
| Check Point SMS | Gaia R81.20 (custom, from SSM) | m5.xlarge |
| Check Point GW1 | Gaia R81.20 (custom, from SSM) | c5.xlarge |
| Check Point GW2 | Gaia R81.20 (custom, from SSM) | c5.xlarge |
| Windows Jump Server | Windows Server 2022 | t3.medium |
| Web Server | Amazon Linux 2 | t3.micro |
| App Server | Amazon Linux 2 | t3.micro |

All instances use the ec2-ssm instance profile and have SSM enabled.

Acceptance criteria: All instances launch and appear healthy in EC2 console." \
  "$M1" "terraform" "aws"

create_issue \
  "Configure three ENIs per Check Point gateway" \
  "Each gateway requires three ENIs to keep management traffic separate from data plane traffic:

- **eth0**: \`fw-external-subnet\` (untrusted/external interface)
- **eth1**: \`fw-internal-subnet\` (trusted/internal interface)
- **eth2**: \`mgmt-subnet\` (management interface — used for SIC and policy push)

Source/destination check must be **disabled** on eth0 and eth1 to allow traffic forwarding.

Acceptance criteria: Each gateway has 3 ENIs, source/dest check disabled on data plane interfaces, SMS can reach each gateway's mgmt ENI." \
  "$M1" "terraform" "networking" "checkpoint" "aws"

create_issue \
  "Configure SSM Session Manager access for all instances" \
  "Ensure all EC2 instances are reachable via AWS SSM Session Manager — no SSH ports or bastion required.

- Verify SSM agent is installed and running on all instances (pre-installed on Amazon Linux 2, RHEL 9, and Windows Server 2022)
- Configure SSM VPC endpoints if instances are fully private with no internet route
- Test SSH access: \`aws ssm start-session --target <instance-id>\`
- Test RDP tunnel to Windows box: \`aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters portNumber=3389,localPortNumber=3389\`

Acceptance criteria: All instances reachable via SSM. No security groups require open SSH or RDP ports." \
  "$M1" "aws" "networking" "security"

create_issue \
  "Write and validate deploy.sh and teardown.sh" \
  "Implement \`scripts/deploy.sh\` and \`scripts/teardown.sh\`:

**deploy.sh** should:
1. Check prerequisites (terraform, ansible, aws cli, gh cli)
2. Run \`terraform init && terraform apply -auto-approve\`
3. Extract outputs (IPs) and write dynamic Ansible inventory
4. Run Ansible playbooks in sequence (01 → 04)

**teardown.sh** should:
1. Run \`terraform destroy -auto-approve\`
2. Optionally clean up SSM parameters and AMI (prompt user)

Acceptance criteria: \`bash scripts/deploy.sh\` completes without manual intervention from a clean state. \`bash scripts/teardown.sh\` destroys all resources." \
  "$M1" "terraform" "ansible" "aws"

# ── Phase 2: Check Point Bootstrap ───────────────────────────────────────────
echo ""
echo "  Phase 2: Check Point Bootstrap"

create_issue \
  "Automate Gaia first-time wizard via EC2 user-data" \
  "Write a \`clish\` script embedded in each gateway's EC2 user-data to automate the Gaia first-time wizard:

- Set hostname
- Configure interface IP addresses
- Set default route
- Retrieve and set SIC activation key from SSM Parameter Store
- Save config

The SMS first-time wizard is simpler (no gateway interfaces) but also needs automating.

Acceptance criteria: Instances boot without requiring manual wizard completion. SIC key is set on each gateway." \
  "$M2" "checkpoint" "ansible" "aws"

create_issue \
  "Enable Check Point Management API on SMS" \
  "Add a task to \`ansible/playbooks/02-bootstrap-checkpoint.yml\` to enable the Check Point Management API.

The API is disabled by default on a fresh SMS. Enable via \`cpconfig\` in batch mode and restrict access to the AAP server's IP address only.

This is a prerequisite for all \`check_point.mgmt\` Ansible module usage.

Acceptance criteria: \`curl -k https://<sms-ip>/web_api/show-api-versions\` returns a valid response from the AAP server." \
  "$M2" "checkpoint" "ansible"

create_issue \
  "Establish SIC between SMS and both gateways" \
  "Implement \`ansible/playbooks/03-establish-sic.yml\` to establish Secure Internal Communication:

1. Wait/poll until each gateway's mgmt ENI is reachable from the SMS
2. Use \`cp_mgmt_simple_gateway\` module to add each gateway to the SMS with the vaulted SIC key
3. Verify SIC status shows as \`communicating\`

The SIC key must match what was set in the gateway user-data script.

Acceptance criteria: Both gateways show as \`communicating\` in SmartConsole." \
  "$M2" "checkpoint" "ansible"

create_issue \
  "Install SmartConsole on Windows jump server" \
  "Add a task to the Windows bootstrap playbook to download and install SmartConsole R81.20 on the Windows jump server.

SmartConsole installer can be downloaded from the Check Point UserCenter or from the SMS directly (\`https://<sms-ip>\`).

Acceptance criteria: SmartConsole launches and connects to the SMS using the admin credentials stored in Ansible Vault." \
  "$M2" "checkpoint" "ansible" "aws"

create_issue \
  "Push initial baseline policy package to both gateways" \
  "Implement \`ansible/playbooks/04-push-initial-policy.yml\` to:

1. Create a baseline policy package on the SMS (minimal rules — block all, allow management traffic)
2. Publish the policy
3. Install the policy to both gateways
4. Verify installation succeeds

This establishes the clean baseline that \`reset-demo.yml\` restores to between customers.

Acceptance criteria: Both gateways show the baseline policy as installed in SmartConsole." \
  "$M2" "checkpoint" "ansible"

# ── Phase 3: AAP Configuration ────────────────────────────────────────────────
echo ""
echo "  Phase 3: AAP Configuration"

create_issue \
  "Install Ansible Automation Platform via installer bundle" \
  "Implement \`ansible/playbooks/01-configure-aap.yml\` to:

1. Retrieve the AAP installer bundle from S3
2. Run the AAP installer in single-node mode
3. Configure the admin password (from Ansible Vault)
4. Verify the AAP web UI is accessible

Acceptance criteria: AAP web UI accessible, admin login works, controller is healthy." \
  "$M3" "aap" "ansible"

create_issue \
  "Deploy check_point.mgmt Ansible collection" \
  "Configure \`ansible/collections/requirements.yml\` and ensure the \`check_point.mgmt\` collection (version >=5.0.0) is installed in the AAP execution environment.

Test collection availability by running a simple \`cp_mgmt_login\` task against the SMS.

Acceptance criteria: \`ansible-galaxy collection list\` shows \`check_point.mgmt\` installed. Login task succeeds." \
  "$M3" "aap" "ansible" "checkpoint"

create_issue \
  "Configure AAP inventory and credentials" \
  "In AAP:

- Create an inventory pointing at the Check Point SMS
- Create a credential of type \`Network\` for the Check Point API (username/password from Ansible Vault)
- Create a credential of type \`Machine\` for SSH access where needed
- Verify inventory sync works and the SMS host is reachable

Acceptance criteria: AAP inventory shows SMS as reachable. Credentials pass validation." \
  "$M3" "aap" "ansible" "checkpoint"

create_issue \
  "Create 'Add Perimeter Rule' job template with Survey" \
  "Create an AAP job template for \`ansible/playbooks/demo/add-perimeter-rule.yml\` with a Survey containing:

- Rule name (text)
- Source IP / network (text)
- Destination IP / network (text)
- Service / port (text)
- Action (choice: allow / drop)

The playbook should: create network objects → create the access rule → publish → install policy to both gateways.

Acceptance criteria: Job template runs successfully. Rule appears in SmartConsole. Traffic behaves as expected." \
  "$M3" "aap" "ansible" "checkpoint" "demo"

create_issue \
  "Create 'Add Internal Rule' job template with Survey" \
  "Create an AAP job template for \`ansible/playbooks/demo/add-internal-rule.yml\` with the same Survey structure as the perimeter rule template, pre-populated for the WebServers → AppServers :8080 use case.

Acceptance criteria: Job template runs successfully. Web server can reach app server on port 8080 only after the rule is applied." \
  "$M3" "aap" "ansible" "checkpoint" "demo"

create_issue \
  "Create 'Modify Rule' job template with Survey" \
  "Create an AAP job template for \`ansible/playbooks/demo/modify-rule.yml\` with a Survey containing:

- Rule name to modify (text)
- New source IP / network (text)

The playbook should find the rule by name, update the source, publish, and reinstall.

Acceptance criteria: Rule source is updated in SmartConsole after job runs." \
  "$M3" "aap" "ansible" "checkpoint" "demo"

create_issue \
  "Create 'Emergency Block' job template with Survey" \
  "Create an AAP job template for \`ansible/playbooks/demo/emergency-block.yml\` with a Survey containing:

- IP address to block (text)

The playbook should create a drop rule at the **top** of the policy (position 1), publish, and install.

Acceptance criteria: Traffic from the specified IP is blocked on both gateways within seconds of job completion." \
  "$M3" "aap" "ansible" "checkpoint" "demo"

create_issue \
  "Create 'Reset Demo' job template" \
  "Create an AAP job template for \`ansible/playbooks/demo/reset-demo.yml\`.

The playbook should:
1. Delete all demo-created rules by name (using a known naming convention, e.g. \`DEMO-*\`)
2. Delete all demo-created network objects
3. Publish
4. Reinstall the baseline policy package

Acceptance criteria: After reset, SmartConsole shows only the baseline policy. All demo traffic tests fail (correctly)." \
  "$M3" "aap" "ansible" "checkpoint" "demo"

# ── Phase 4: Demo Hardening ───────────────────────────────────────────────────
echo ""
echo "  Phase 4: Demo Hardening"

create_issue \
  "End-to-end test of all five demo scenarios" \
  "Run through each demo scenario in sequence and verify outcomes:

1. Add Perimeter Rule → traffic allowed, visible in SmartLog
2. Add Internal Rule → web-to-app traffic works on :8080
3. Modify Rule → source restricted, SmartConsole updated
4. Emergency Block → traffic blocked within seconds
5. Reset Demo → all rules removed, baseline restored

Document any issues found and fix before sign-off.

Acceptance criteria: All five scenarios complete without error. SmartConsole and SmartLog reflect expected state after each." \
  "$M4" "demo" "checkpoint" "ansible"

create_issue \
  "Validate reset-demo.yml between scenario runs" \
  "Run the reset playbook after each scenario and confirm the environment returns to a clean baseline before the next scenario is run.

Verify:
- All DEMO-* rules are gone from SmartConsole
- All DEMO-* network objects are gone
- Baseline policy is installed on both gateways
- All traffic tests fail as expected (confirming the baseline blocks by default)

Acceptance criteria: Reset takes under 60 seconds. Environment is indistinguishable from a fresh bootstrap." \
  "$M4" "demo" "ansible" "checkpoint"

create_issue \
  "Test deploy.sh and teardown.sh from a clean AWS account" \
  "Perform a full cycle test:

1. Ensure no resources exist beyond the S3 state bucket and DynamoDB table
2. Run \`bash scripts/deploy.sh\` — time the full deployment
3. Verify all instances are accessible and demo scenarios work
4. Run \`bash scripts/teardown.sh\` — verify all resources are destroyed
5. Run deploy again to confirm repeatability

Acceptance criteria: Full deploy completes in under 45 minutes. Teardown leaves no billable resources (excluding S3/DynamoDB). Second deploy is identical to first." \
  "$M4" "terraform" "ansible" "aws"

create_issue \
  "Write demo run sheet" \
  "Write a concise demo run sheet (\`DEMO_RUNSHEET.md\`) covering:

- Pre-demo checklist (environment up, SmartConsole open, SmartLog tab visible, browser tabs ready)
- Scenario talking points and expected outcomes (one page per scenario)
- Fallback steps if something fails during a live demo
- Reset procedure between customers

The run sheet should be usable by anyone delivering the demo, not just the person who built it.

Acceptance criteria: A colleague unfamiliar with the build can run the demo successfully using only the run sheet." \
  "$M4" "demo" "documentation"

# ── Phase 5: AlgoSec ─────────────────────────────────────────────────────────
echo ""
echo "  Phase 5: AlgoSec Integration"

create_issue \
  "Deploy AlgoSec Firewall Analyzer" \
  "Deploy AlgoSec AFA into the demo environment (requires an evaluation licence from AlgoSec).

AlgoSec can be deployed as a virtual appliance — follow a similar OVA import process to the Check Point gateways.

Acceptance criteria: AlgoSec AFA web UI accessible. SMS visible in AFA as a managed device." \
  "$M5" "algosec" "aws"

create_issue \
  "Integrate AlgoSec with Check Point SMS" \
  "Configure AlgoSec AFA to connect to the Check Point SMS and pull the current policy.

Verify that AlgoSec correctly displays the existing rules and can perform risk analysis queries.

Acceptance criteria: AlgoSec shows the current Check Point policy. Risk analysis returns results for test queries." \
  "$M5" "algosec" "checkpoint"

create_issue \
  "Add AlgoSec risk analysis gate to Ansible playbooks" \
  "Extend the demo playbooks (add-perimeter-rule.yml, add-internal-rule.yml) to call the AlgoSec API before pushing a rule change:

1. Submit the proposed rule to AlgoSec for risk analysis
2. If risk is flagged → fail the playbook with a clear error message
3. If clean → proceed with rule creation and policy push

Acceptance criteria: A high-risk rule (e.g. any→any :any allow) is blocked by the AlgoSec gate. A low-risk rule proceeds as normal." \
  "$M5" "algosec" "ansible" "checkpoint" "demo"

create_issue \
  "Update demo scenarios to include AlgoSec story" \
  "Update \`PLAN.md\` and \`DEMO_RUNSHEET.md\` to incorporate AlgoSec into the demo flow:

- Show a rule being blocked by AlgoSec risk analysis
- Show a clean rule passing through the gate
- Update talking points to cover regulated industry use cases

Acceptance criteria: Demo run sheet updated. AlgoSec scenario tested end-to-end." \
  "$M5" "algosec" "demo" "documentation"

# ── Phase 6: ServiceNow ───────────────────────────────────────────────────────
echo ""
echo "  Phase 6: ServiceNow Self-Service"

create_issue \
  "Set up ServiceNow Personal Developer Instance" \
  "Register for and provision a ServiceNow Personal Developer Instance (PDI) at https://developer.servicenow.com.

Configure basic instance settings and verify admin access.

Acceptance criteria: ServiceNow PDI accessible. Admin login works." \
  "$M6" "servicenow"

create_issue \
  "Create Firewall Rule Request catalogue item in ServiceNow" \
  "Build a Service Catalogue item in ServiceNow for firewall rule requests with fields:

- Request name / description
- Source IP or network
- Destination IP or network
- Port / service
- Business justification
- Urgency

Acceptance criteria: Catalogue item is publishable and submittable by a test user." \
  "$M6" "servicenow" "demo"

create_issue \
  "Build approval workflow in ServiceNow" \
  "Configure a ServiceNow Flow or Workflow to route firewall rule requests through:

1. Manager approval
2. Security team approval
3. On final approval → trigger AAP webhook

Acceptance criteria: Test submission routes correctly through approvals. Rejection sends a notification to the requester." \
  "$M6" "servicenow"

create_issue \
  "Configure ServiceNow webhook to trigger AAP on approval" \
  "Use a ServiceNow scripted REST message or IntegrationHub REST step to call the AAP API on workflow approval, passing rule parameters as variables.

AAP API endpoint: \`https://<aap-server>/api/v2/job_templates/<id>/launch/\`

Acceptance criteria: Approving a request in ServiceNow triggers an AAP job. The firewall rule is created automatically. The ServiceNow ticket is updated with the job outcome." \
  "$M6" "servicenow" "aap" "ansible"

create_issue \
  "End-to-end test of full ServiceNow → AAP → Check Point flow" \
  "Run a complete end-to-end test:

1. Submit firewall rule request via ServiceNow catalogue
2. Approve through the workflow
3. Verify AAP job is triggered automatically
4. Verify AlgoSec risk check runs (if Phase 5 complete)
5. Verify rule appears in Check Point SmartConsole
6. Verify ServiceNow ticket is closed with success details

Acceptance criteria: Full flow completes without manual intervention. All systems reflect the correct state." \
  "$M6" "servicenow" "aap" "algosec" "checkpoint" "demo"

# =============================================================================
echo ""
echo "================================================="
echo " ✅  Backlog created successfully!"
echo "     View at: https://github.com/$REPO/issues"
echo "     Milestones: https://github.com/$REPO/milestones"
echo "================================================="
echo ""
