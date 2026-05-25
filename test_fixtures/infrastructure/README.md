# Fixtures — Infrastructure

Bundled **Terraform** that stands up **scan targets** — the assets Prooflayer
points at — paired with the [credentials](../credentials/README.md) that reach
them. Each plants **deliberate drift** so a scan produces real findings, not just
green checks (a demo where everything passes proves nothing).

> Modules use your ambient `az login` / AWS CLI context. State is git-ignored.
> These create **real, billable** cloud resources — `terraform destroy` when
> done. Provided as-is; apply in your own cloud to validate.

## The modules

| Module | Provisions | Drift planted | Scan with |
|---|---|---|---|
| [azure-target/](azure-target/README.md) | An Azure storage account (+ resource group) with configurable TLS/HTTPS knobs. | flip `https_only=false` / `min_tls=TLS1_0` to fail the storage policy | `azure_spn` credential + the bundled Azure storage policy |
| [aws-target/](aws-target/README.md) | Two S3 buckets — one locked-down, one weak. | the weak bucket has no default encryption, versioning off, public-access block disabled | `aws_access_key`/`aws_role` + the bundled `aws_s3_bucket` policy |

Both are minimal and cheap. For a richer, multi-tenant story (hub + drifting
tenant spokes), AKS/EKS clusters, a single SSH VM, or a local `kind` cluster,
see the broader fixture tiers summarized in
[../README.md](../README.md) (Tiers 1–2).

## Outputs → register as assets

Each module emits the identifiers you register (or let discovery enumerate):

- **azure-target** → `storage_account_name` / `storage_account_id` (+ resource
  group, subscription) and a `settings_summary` of what was set.
- **aws-target** → `compliant_bucket`, `drift_bucket`, `region` (and
  `register_as_assets` = both names).

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
