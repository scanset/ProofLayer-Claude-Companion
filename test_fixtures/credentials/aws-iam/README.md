# Prooflayer scanning IAM principal — Terraform

Provisions an AWS principal that Prooflayer uses to scan AWS resources.
Mirrors the azure-spn fixture, for AWS. Two modes:

| Mode | What it produces | Use when |
|---|---|---|
| **`assume_role`** *(default)* | IAM role + trust policy + required external_id | **Production / SaaS.** The Prooflayer VM's instance role assumes this role via STS. No long-lived secrets. The canonical AWS third-party scanner pattern. |
| **`access_key`** | IAM user + rotating programmatic access keys | Dev / POC. Faster bootstrap, but produces long-lived static credentials. |

Both modes attach the AWS-managed `SecurityAudit` policy by default —
read-only access scoped for security assessments, equivalent to Azure
`Reader`. Sufficient for the ~38 AWS collectors in `assessor-core`
(ec2, s3, iam, cloudtrail, config, cloudwatch, guardduty, etc.).

## Usage

```bash
cd test_fixtures/credentials/aws-iam

# Pre-req: an AWS identity with IAM write permissions (e.g. AdministratorAccess
# or a scoped IAM-management role). Configure via env, profile, or SSO:
export AWS_PROFILE=my-admin-profile     # or aws sso login

terraform init
terraform apply                          # default: assume_role mode
```

Override the mode and other variables with `-var`:

```bash
terraform apply -var='credential_kind=access_key'

# Cross-account: trust the Prooflayer SaaS account, not the customer's own
terraform apply \
  -var='credential_kind=assume_role' \
  -var='trusted_principal_arns=["arn:aws:iam::123456789012:root"]'
```

## Get the values for Prooflayer

```bash
terraform output                          # all non-sensitive values
terraform output -raw external_id         # assume_role mode
terraform output -raw secret_access_key   # access_key mode
```

## Pasting into Prooflayer

In the system UI: **Admin → Credentials → Add credential**.

### `assume_role` mode

| Form field | Source |
|---|---|
| Name | Pick something like `aws-prod-scanner` |
| Kind | `AWS Role` |
| Role ARN | `terraform output -raw role_arn` |
| External ID | `terraform output -raw external_id` |
| Source profile | *(leave empty)* — defaults to the VM's instance role |
| Metadata `region` | `terraform output -raw region` |

The Prooflayer resolver materializes an AWS CLI config file in the
per-scan tempdir using `credential_source = Ec2InstanceMetadata` by
default, so the **Prooflayer VM's IAM instance role** is what calls
`sts:AssumeRole`. No static keys exist on the VM.

For non-EC2 deployments, set credential metadata
`credential_source = "Environment"` and supply
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` to the Prooflayer process at
deploy time (e.g. via systemd EnvironmentFile).

### `access_key` mode

| Form field | Source |
|---|---|
| Name | Pick something like `aws-dev-scanner` |
| Kind | `AWS Access Key` |
| Access key ID | `terraform output -raw access_key_id` |
| Secret access key | `terraform output -raw secret_access_key` |
| Metadata `region` | `terraform output -raw region` |

## Variables

| Name | Default | Purpose |
|---|---|---|
| `credential_kind` | `assume_role` | `assume_role` or `access_key` |
| `iam_name` | `prooflayer-scanner` | Name for the IAM role or user |
| `region` | `us-east-1` | Default region passed through to credential metadata |
| `managed_policy_arns` | `[SecurityAudit]` | Managed policies attached to the role/user |
| `trusted_principal_arns` | current account root | (assume_role) Principals allowed to call AssumeRole |
| `external_id` | auto-generated 32-char string | (assume_role) Confused-deputy guard |
| `key_validity_months` | `12` | (access_key) Auto-rotation interval for the access key |

## Rotation

### `assume_role`

The role itself doesn't expire — STS issues fresh temp credentials on
every `AssumeRole` call. To rotate the **external_id**:

```bash
terraform apply -var='external_id=NEW-VALUE-HERE'
```

Then update the credential in Prooflayer using the **Rotate** button.

### `access_key`

Re-running `terraform apply` after `key_validity_months` flips the
`time_rotating` resource and replaces the access key. Update the
credential in Prooflayer using the **Rotate** button — `secret_access_key`
is the only field that changes; `access_key_id` is replaced too.

## Tearing down

```bash
terraform destroy
```

In `assume_role` mode this removes the role and its managed policy
attachments. In `access_key` mode it removes the user, the access key,
and the policy attachments.

## Adding broader scan permissions later

`SecurityAudit` covers most read-only assessments but not data-plane
reads (e.g. S3 GetObject, KMS Decrypt). To extend:

```bash
terraform apply \
  -var='managed_policy_arns=["arn:aws:iam::aws:policy/SecurityAudit","arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]'
```

Or attach a custom inline policy out-of-band:

```hcl
resource "aws_iam_role_policy" "scanner_extras" {
  count = local.is_assume_role ? 1 : 0
  role  = aws_iam_role.scanner[0].name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject"],
      Resource = ["arn:aws:s3:::my-bucket/*"]
    }]
  })
}
```

## VM instance role (production deployment)

The `assume_role` flow assumes the Prooflayer VM has its own IAM
instance role with permission to call `sts:AssumeRole` on the scanner
role. That instance role is **not** created by this module — it lives
with the VM provisioning (the infrastructure target fixtures
or your production deployment).

The instance role needs at minimum:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::*:role/prooflayer-scanner"
  }]
}
```

Plus whatever it needs to read its own bootstrap secrets from Secrets
Manager (DB URL, evidence writer credentials, JWT secrets) at boot.
