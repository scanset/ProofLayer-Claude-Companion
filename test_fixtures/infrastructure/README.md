# Fixtures — Infrastructure

Bundled **Terraform** that stands up **scan targets** — the assets Prooflayer
points at — paired with the [credentials](../credentials/README.md) that reach
them. Each plants **deliberate drift** so a scan produces real findings, not just
green checks (a demo where everything passes proves nothing).

> Modules use your ambient `az login` / AWS CLI context. State is git-ignored.
> These create **real, billable** cloud resources — `terraform destroy` when
> done. Provided as-is; apply in your own cloud to validate.

## The modules

| Module | Provisions | Channel(s) exercised | Scan with |
|---|---|---|---|
| [azure-target/](azure-target/README.md) | An Azure storage account (+ resource group) with configurable TLS/HTTPS knobs (flip them to fail the policy). | `local` (cloud API) | `azure_spn` credential + the bundled Azure storage policy |
| [aws-target/](aws-target/README.md) | Two S3 buckets — one locked-down, one deliberately weak. | `local` (cloud API) | `aws_access_key`/`aws_role` + the bundled `aws_s3_bucket` policy |
| [host-targets/](host-targets/README.md) | **Three real hosts (AWS)** — Ubuntu 22.04, Rocky 9, Windows Server 2022 — in one VPC. **Generates the SSH keypair** (export it into an `ssh_key` credential) and the Windows admin password. | **`ssh`** (Linux) + **`winrm`** (Windows) | `ssh_key` + `winrm_password` (generated); `aws_*` cred for discovery |
| [azure-host-targets/](azure-host-targets/README.md) | **Three real hosts (Azure)** — Ubuntu 22.04, RHEL 9, Windows Server 2022 — in one **resource group** (cleaner discovery hierarchy). Same generated SSH key + Windows password. | **`ssh`** (Linux) + **`winrm`** (Windows) | `ssh_key` + `winrm_password` (generated); `azure_spn` cred for discovery |

aws-target / azure-target are cloud control-plane (`local` channel) and cheap.
**host-targets** (AWS) and **azure-host-targets** (Azure) are the ones that
exercise the *host* channels (`ssh` + `winrm`) and the multi-OS
discover-and-link story — pick whichever cloud you prefer (Azure's resource-group
hierarchy links most cleanly). For a richer multi-tenant landing zone, managed
AKS/EKS, or a local `kind` cluster, see the build-your-own progression in
[../suggestions.md](../suggestions.md).

## Outputs → register as assets

Each module emits the identifiers you register (or let discovery enumerate):

- **azure-target** → `storage_account_name` / `storage_account_id` (+ resource
  group, subscription) and a `settings_summary` of what was set.
- **aws-target** → `compliant_bucket`, `drift_bucket`, `region` (and
  `register_as_assets` = both names).
- **host-targets** / **azure-host-targets** → `hosts` (the three hosts + channel
  + login user + public address), `ssh_private_key_pem` / `ssh_key_file` (the
  generated key — paste or download), `windows_username` / `windows_password`,
  and the container they link under (`vpc_id`/`subnet_id` on AWS,
  `resource_group_name`/`vnet_id` on Azure).

## Wiring into Prooflayer

1. Deploy the matching **credential** first ([../credentials/](../credentials/README.md)),
   then `terraform apply` the target module here.
2. Either **discover** the targets (run the matching provider discovery with the
   credential) or register the output ids directly as assets.
3. **Auto-link** (by `target_asset_type`) or link the relevant policy explicitly,
   then scan — see
   [usage/workflows/auto-link-and-assignment.md](../../usage/workflows/auto-link-and-assignment.md)
   and [scanning-and-evidence.md](../../usage/workflows/scanning-and-evidence.md).
4. Confirm the planted drift shows up as a **fail** finding and the compliant
   resource **passes**, each a signed proof; re-running an unchanged target
   reproduces the same [replay hash](../../components/replay-hash.md).
5. `terraform destroy` — tear targets down with their credentials; don't leave
   eval identities or resources behind.
