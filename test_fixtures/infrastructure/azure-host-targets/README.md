# azure-host-targets — Ubuntu + RHEL 9 + Windows Server (the host channels)

The Azure twin of [host-targets](../host-targets/README.md). Same idea — three
real hosts so you can exercise the **host channels** and watch multi-OS assets
discover and link — but on Azure, where the **resource-group hierarchy** gives
discovery a clean tree to attach to:

| Host | Channel | Credential to scan with | Policy platform |
|---|---|---|---|
| **Ubuntu 22.04** | `ssh` | `ssh_key` (generated here) | `ubuntu` / `ubuntu22` |
| **RHEL 9** | `ssh` | `ssh_key` (generated here) | `rhel9` / `rocky9` |
| **Windows Server 2022** | `winrm` | `winrm_password` (generated here) | `windows` / `windows_server` |

All three sit in **one resource group + VNet**, so Azure discovery enumerates the
subscription and links them under the RG (Subscription → Resource Group → VMs /
VNet / NICs / public IPs) — the cleanest version of the asset-graph story.

> **Real, billable resources** — three small VMs. `terraform destroy` when done.
> Auth uses your ambient `az login` context (or set `subscription_id`).
> **Eval-grade only**: the generated SSH key and Windows password are for a
> throwaway demo — never reuse them.

---

## 1. Deploy

```bash
az login                                       # if not already
cp terraform.tfvars.example terraform.tfvars   # optional: region, lock down allowed_cidr
terraform init
terraform apply
terraform output                               # the three hosts + their public IPs
```

> **Reachability:** the appliance must reach the VMs on `22` (Linux) and `5985`
> (Windows). `allowed_cidr` defaults to `0.0.0.0/0` for a demo — set it to the
> appliance's public egress IP for anything longer-lived. The Windows VM runs a
> first-boot extension to enable WinRM; give it a few minutes after `apply`.

## 2. Get the SSH key (paste or download)

Terraform **generated** the keypair and installed the public half on both Linux
VMs:

```bash
terraform output -raw ssh_private_key_pem      # paste into the credential form
terraform output -raw ssh_key_file             # or download ./prooflayer-eval-key.pem
```

## 3. Upload credentials into Prooflayer

system-ui → **Credentials → New**:

- **`ssh_key`** — `eval-ssh`, paste the PEM. SSH user is `azureuser` (the
  `linux_admin_username`). Used for **both** Linux VMs.
  ([ssh_key](../../../usage/credentials/ssh_key.md).)
- **`winrm_password`** — `eval-winrm`; username `azureadmin`, password from
  `terraform output -raw windows_password`.
  ([winrm_password](../../../usage/credentials/winrm_password.md).)
- An **`azure_spn`** credential (from the
  [azure-spn](../../credentials/azure-spn/README.md) fixture) so discovery can
  enumerate the subscription.

## 4. Discover → watch them link

Run **Azure discovery** (system-ui → **Discover**, or
`POST /api/inventory/discover/local` with the `azure_spn` credential). Discovery
walks the subscription and records the hierarchy: the **resource group
`contains`** the VNet and the three VMs; each VM `references` its NIC / public IP
and the subnet it sits on. Open the **Assets** page (or
[Pathfinder](../../../components/pathfinder.md)) and the three hosts appear
grouped under the one resource group — the
[link taxonomy](../../../components/inventory.md#the-asset-graph--link-taxonomy)
made obvious. (No SPN handy? Register each VM by hand via
`POST /api/inventory/assets` using the public IPs from `terraform output`.)

## 5. Set each host's channel + credential, then assign policies

On each discovered VM (**Asset Detail → Edit**):

- **Ubuntu** and **RHEL 9** → channel **`ssh`**, credential **`eval-ssh`**, SSH
  user `azureuser`.
- **Windows** → channel **`winrm`**, credential **`eval-winrm`**. (For a VM with
  no inbound WinRM you'd use **`az-bastion`** instead — same credential.)

Then **assign the matching policies** — auto-link by platform, or by hand: the
`ubuntu` set to Ubuntu, the `rhel9`/`rocky9` set to RHEL, the `windows` set to
Windows. See [auto-link & assignment](../../../usage/workflows/auto-link-and-assignment.md)
and [channels](../../../components/channels.md).

## 6. Scan

Test-Scan each host, or run a [fleet Posture Scan](../../../usage/workflows/scanning-and-evidence.md#posture-scan--the-fleet-run).
Each dispatch reaches the VM over its channel, runs the OS policy set, and
produces a signed, replayable proof per host.

---

## Tear down

```bash
terraform destroy
```

Deletes the VMs, the RG, the network, and the local `.pem`. Also delete the
`eval-ssh` / `eval-winrm` credentials in Prooflayer afterward.

## Notes & caveats

- **WinRM is eval-grade.** The first-boot extension enables WinRM **basic auth
  over HTTP** (`AllowUnencrypted`) so the `winrm` channel's basic mode connects
  without TLS plumbing. Never do this on a real host.
- **RHEL by default, Rocky optional.** The RPM host uses the **first-party RHEL 9**
  image (PAYG, no Marketplace agreement). For Rocky 9, point the `rhel_*` vars at
  the resf Marketplace image and add an `azurerm_marketplace_agreement` + a `plan`
  block (the `rhel9` and `rocky9` policy platforms are the same family).
- **Remote host-mode gap (alpha):** a few host-mode CTNs aren't yet channel-aware
  on remote scans — see
  [channels § known gap](../../../components/channels.md#known-gap-be-honest-in-the-alpha).
- **Cost:** three small VMs. Stop or destroy them when not actively evaluating.
