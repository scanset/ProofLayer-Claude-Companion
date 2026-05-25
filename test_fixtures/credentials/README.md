# Fixtures — Credentials

Bundled **Terraform** that mints the **least-privilege credentials** you register
in Prooflayer so the scanner can reach the
[infrastructure fixtures](../infrastructure/README.md). A credential is reusable
across many targets and rotates on its own cadence (the inventory model's first
concept — [components/inventory.md](../../components/inventory.md)).

> These modules use your existing `az login` / AWS CLI context — no
> Terraform-side secrets. Each emits, via `terraform output`, exactly the fields
> Prooflayer's **Add credential** form expects. State and rendered secrets are
> git-ignored; never commit `*.tfstate`. Modules are provided as-is — apply them
> in your own cloud to validate.

## The modules

| Module | Provisions | Prooflayer credential kind(s) it feeds |
|---|---|---|
| [azure-spn/](azure-spn/README.md) | An Entra app registration + service principal with **Reader** at subscription scope, a client secret, a cert-bound SPN, and a delegated (public-client) app reg. One apply. | `azure_spn` (secret), `azure_spn_cert` (cert), `m365_delegated_refresh` (delegated) |
| [aws-iam/](aws-iam/README.md) | A read-only IAM **role** (assume) *or* **user** (static key) — toggle with `credential_kind` — attached to read-only managed policies (`SecurityAudit` / `ViewOnlyAccess`). | `aws_role` or `aws_access_key` |

These cover the common cloud eval path. Other credential kinds (`ssh_key`,
`winrm_password`, `gcp_sa_key`, `github_pat`, `kube_config`, `network_target`)
are provisioned outside Terraform or with their own tooling — their payload
fields and how-to-obtain are in the per-kind reference under
[../../usage/credentials/](../../usage/credentials/README.md).

## Output → credential mapping (turnkey)

Each module's `terraform output` maps straight to credential payload fields:

- **azure-spn** → `client_id`, `tenant_id`, `client_secret` (→ `azure_spn`);
  `pwsh_client_id`, `pwsh_certificate`, `pwsh_private_key` (→ `azure_spn_cert`);
  `delegated_client_id`, `tenant_id` (→ `m365_delegated_refresh`, which then runs
  its device-code flow). Plus `subscription_id` for the credential's metadata.
- **aws-iam** → `role_arn` + `external_id` (→ `aws_role`) **or** `access_key_id`
  + `secret_access_key` (→ `aws_access_key`), plus `region`/`account_id` metadata.

## Wiring into Prooflayer

1. `cd` into the module, `cp terraform.tfvars.example terraform.tfvars` (edit if
   needed), `terraform init && terraform apply`.
2. Read the values: `terraform output` (or `terraform output -json | jq` to avoid
   scrollback). The secret outputs are marked `sensitive`.
3. In **system-ui → Admin → Credentials → Add credential**, pick the kind and
   paste the payload — see
   [usage/workflows/credentials.md](../../usage/workflows/credentials.md).
4. Run **discovery** against the credential to populate assets
   ([usage/workflows/discovery.md](../../usage/workflows/discovery.md)), then pair
   it with a target from [../infrastructure/](../infrastructure/README.md).
5. `terraform destroy` when done — a credential is live access; tear it down with
   its targets.

> **Least privilege:** both modules default to **read-only** (Reader / SecurityAudit
> / ViewOnlyAccess). That's all discovery + scanning need, and it keeps the
> scanner's blast radius minimal. Don't widen them for an evaluation.
