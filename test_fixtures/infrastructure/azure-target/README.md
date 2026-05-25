# Prooflayer test target — minimal Azure resources

Provisions a compliant storage account that the smoke-test ESP policy
scans against. Creates and tears down in ~30 seconds. Costs essentially
nothing while empty.

## What gets created

- One resource group (`prooflayer-test-rg` by default)
- One storage account, named `<prefix><random6hex>` for global uniqueness
  - `https_traffic_only_enabled = true`
  - `min_tls_version = TLS1_2`
  - `allow_nested_items_to_be_public = false`
  - LRS replication, Standard tier (cheapest)

Both tagged `purpose=prooflayer-smoke-test`.

## Usage

```bash
cd test_fixtures/infrastructure/azure-target
terraform init
terraform apply
```

After apply:

```bash
terraform output                       # show all
terraform output -raw storage_account_name
```

Use the output values to populate the test ESP policy
(a bundled Azure storage policy).

## Verify a failing scan

To intentionally produce a non-compliant resource for testing the
"policy correctly detects failure" path:

```bash
terraform apply -var='https_only=false' -var='min_tls=TLS1_0'
```

Then re-run the test scan from the UI — both policy assertions should fail.

## Tearing down

```bash
terraform destroy
```

Removes the storage account first, then the resource group. Idempotent.

## Variables

| Name | Default | Purpose |
|---|---|---|
| `subscription_id` | active az login sub | Where the resources land |
| `resource_group_name` | `prooflayer-test-rg` | RG name |
| `location` | `eastus` | Azure region |
| `storage_name_prefix` | `pltest` | Prepended to a 6-hex random suffix |
| `https_only` | `true` | HTTPS-only requirement (flip to `false` to fail) |
| `min_tls` | `TLS1_2` | Minimum TLS version (`TLS1_0`/`TLS1_1` to fail) |

## What the SPN needs to scan this

The Azure SPN you provisioned via the azure-spn fixture already has Reader on
the entire subscription, which covers the test resource group + storage
account. No extra role assignment needed.
