# host-targets — Ubuntu + Rocky 9 + Windows Server (the host channels)

The cloud fixtures ([aws-target](../aws-target/README.md),
[azure-target](../azure-target/README.md)) only exercise the **`local`** channel
(scanning a provider's API). This fixture stands up **real hosts** so you can
exercise the **host channels** and watch multi-OS assets discover and link:

| Host | Channel | Credential to scan with | Policy platform |
|---|---|---|---|
| **Ubuntu 22.04** | `ssh` | `ssh_key` (generated here) | `ubuntu` / `ubuntu22` |
| **Rocky 9** | `ssh` | `ssh_key` (generated here) | `rocky9` / `rhel9` |
| **Windows Server 2022** | `winrm` | `winrm_password` (generated here) | `windows` / `windows_server` |

All three sit in **one VPC + subnet**, so AWS discovery enumerates them and links
them under the shared VPC (Account → VPC → Subnet → Instance) — the asset-graph
story end to end.

> **Real, billable resources** — three small EC2 instances. `terraform destroy`
> when done. Auth uses your ambient AWS context. **Eval-grade only**: the SSH key
> and Windows password are generated for a throwaway demo — never reuse them.

---

## 1. Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # optional: region, and lock down allowed_cidr
terraform init
terraform apply
terraform output                               # the three hosts + their addresses
```

> **Reachability:** the appliance must be able to reach the hosts on `22`
> (Linux) and `5985` (Windows). `allowed_cidr` defaults to `0.0.0.0/0` for a
> demo — set it to the appliance's **public egress IP** for anything longer-lived.
> In a NAT'd/WSL2 dev box the container may not route out the way you expect;
> see [network-sweep-discovery](../../../components/network-sweep-discovery.md).

## 2. Get the SSH key (paste or download)

Terraform **generated** the keypair and installed the public half on both Linux
hosts. Get the private key into Prooflayer one of two ways:

```bash
# Paste: copy this into the credential form
terraform output -raw ssh_private_key_pem

# Download: it's also written next to the fixture (chmod 600)
terraform output -raw ssh_key_file        # → ./prooflayer-eval-key.pem
```

## 3. Upload credentials into Prooflayer

system-ui → **Credentials → New** (or `POST /api/inventory/credentials`):

- **`ssh_key`** — name it `eval-ssh`, paste the PEM from step 2. Used for **both**
  Linux hosts. (Reference: [ssh_key](../../../usage/credentials/ssh_key.md).)
- **`winrm_password`** — name it `eval-winrm`; username `Administrator`, password
  from `terraform output -raw windows_password`. (Reference:
  [winrm_password](../../../usage/credentials/winrm_password.md).)

You'll also want a read-only **AWS credential** (from the
[aws-iam](../../credentials/aws-iam/README.md) fixture) so discovery can
enumerate the hosts — register it as `aws_access_key` or `aws_role`.

## 4. Discover → watch them link

Run **AWS discovery** (system-ui → **Discover**, or
`POST /api/inventory/discover/local` with the AWS credential). Discovery
enumerates the account and records the topology — the VPC and its subnet
(`contains`), each instance and the security group / subnet it sits behind
(`references` / `attached_to`). Open the **Assets** page (or
[Pathfinder](../../../components/pathfinder.md)) and you'll see the three hosts
cluster under the shared VPC — that's the
[link taxonomy](../../../components/inventory.md#the-asset-graph--link-taxonomy)
in action. (No cloud creds handy? Register each host by hand via
`POST /api/inventory/assets` using the public IPs from `terraform output`.)

## 5. Set each host's channel + credential, then assign policies

On each discovered host (**Asset Detail → Edit**):

- **Ubuntu** and **Rocky 9** → channel **`ssh`**, credential **`eval-ssh`**,
  SSH user `ubuntu` / `rocky` respectively (from the `hosts` output).
- **Windows** → channel **`winrm`**, credential **`eval-winrm`**.

Then **assign the matching policies** — auto-link by platform, or link by hand:
the `ubuntu` policies to the Ubuntu host, the `rocky9`/`rhel9` set to the Rocky
host, and the `windows` set to the Windows host. See
[auto-link & assignment](../../../usage/workflows/auto-link-and-assignment.md)
and [channels](../../../components/channels.md).

## 6. Scan

Test-Scan each host, or run a [fleet Posture Scan](../../../usage/workflows/scanning-and-evidence.md#posture-scan--the-fleet-run).
Each dispatch reaches the host over its channel, runs the OS policy set, and
produces a signed, replayable proof per host.

---

## Tear down

```bash
terraform destroy
```

This deletes the instances, the VPC, the key pair, and the local `.pem`. Also
delete the `eval-ssh` / `eval-winrm` credentials in Prooflayer once you're done.

## Notes & caveats

- **WinRM is eval-grade.** First boot enables WinRM **basic auth over HTTP**
  (`AllowUnencrypted`) so the `winrm` channel's basic mode connects without TLS
  plumbing. Never do this on a real host. The Windows host takes a few minutes
  after `apply` to finish first boot before WinRM answers.
- **Remote host-mode gap (alpha):** a handful of host-mode CTNs aren't yet
  channel-aware on remote scans — see
  [channels § known gap](../../../components/channels.md#known-gap-be-honest-in-the-alpha).
- **RHEL instead of Rocky:** pass a RHEL 9 AMI id via `rocky_ami` — the `rhel9`
  and `rocky9` policy platforms are the same family.
- **Cost:** three small instances. Stop or destroy them when you're not actively
  evaluating.
