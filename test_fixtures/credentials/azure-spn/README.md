# Prooflayer scanning SPN — Terraform

Provisions an Entra ID service principal for Prooflayer to scan Azure
resources. Uses your local `az login` context — no Terraform-side
credentials needed.

## What gets created

- One Entra ID app registration (`spn_display_name`, default `prooflayer-scanner`)
- One service principal in the tenant
- One client secret (auto-rotated every `secret_validity_months`, default 12)
- One RBAC role assignment: **Reader** at subscription scope

The SPN authenticates against Azure Resource Manager only — no Microsoft
Graph permissions. Sufficient for CIS / STIG ARM scanning. To extend, see
the comments in `main.tf`.

## Usage

```bash
cd test_fixtures/credentials/azure-spn

az login                   # already done — current sub becomes the default
terraform init
terraform apply
```

Override the subscription or display name with `-var`:

```bash
terraform apply \
  -var='subscription_id=2f3a8603-...' \
  -var='spn_display_name=prooflayer-prod'
```

## Get the values for Prooflayer

```bash
terraform output                     # all non-sensitive values
terraform output -raw client_secret  # the secret (one-shot reveal)
```

## Pasting into Prooflayer

In the system UI: **Admin → Credentials → Add credential**.

| Form field | Source |
|---|---|
| Name | Pick something like `azure-prod-reader` |
| Kind | `Azure SPN` |
| Client ID | `terraform output -raw client_id` |
| Tenant ID | `terraform output -raw tenant_id` |
| Client secret | `terraform output -raw client_secret` |
| Metadata `subscription_id` | `terraform output -raw subscription_id` |

Optional metadata: `tenant_display_name` for nicer UI labels.

## Variables

| Name | Default | Purpose |
|---|---|---|
| `subscription_id` | active az login sub | Where to scope the Reader assignment |
| `spn_display_name` | `prooflayer-scanner` | Name in the Entra ID app list |
| `role` | `Reader` | Built-in role assigned at subscription scope |
| `secret_validity_months` | `12` | Auto-rotation interval for the client secret |

## Rotation

When the secret expires, run `terraform apply` again. The `time_rotating`
resource flips, the password resource regenerates, and the new value is
in `terraform output -raw client_secret`. Update the credential in
Prooflayer using the **Rotate** button on the credential row — the
client secret is the only field that changes; client_id and tenant_id
stay the same.

## Tearing down

```bash
terraform destroy
```

Removes the role assignment, the secret, the service principal, and the
app registration.

## Adding broader scan permissions later

Edit `main.tf` and add additional `azurerm_role_assignment` resources, e.g.:

```hcl
resource "azurerm_role_assignment" "scanner_security_reader" {
  scope                = "/subscriptions/${local.subscription_id}"
  role_definition_name = "Security Reader"
  principal_id         = azuread_service_principal.scanner.object_id
}
```

For Entra ID compliance scanning (users, MFA state), add a
`required_resource_access` block to `azuread_application.scanner` for the
Microsoft Graph API and run `az ad app permission admin-consent` after
applying.
