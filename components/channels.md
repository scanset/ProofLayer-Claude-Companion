# Channels

**Status: built (5 channels). Note: 5 host-mode CTNs not yet channel-aware.**

## What it is

A **channel** is the transport abstraction — *how* the scanner reaches a target.
It is pure transport: a channel runs commands / fetches state against a remote
target and hands bytes back. It makes **no** decisions about *what* to check —
that's the CTN's and the policy's job. This orthogonality is deliberate:

> The CTN strategy says **what** to check. The channel says **how** to reach it.
> A scan is a tuple of `(policies, channel, credentials)`.

The same RHEL9 host-mode policy can run over `ssh`, `aws-ssm`, or `az-bastion`
unchanged — only the channel differs.

## The five channels

| Channel | Reaches | Credential | Notes |
|---|---|---|---|
| `local` | the host the engine runs on; also cloud control planes via the provider CLI (`az`/`aws`/`gcloud`/`kubectl`) | none, or a cloud credential consumed by the CLI | Default. Cloud scans are "local channel + provider CLI + cloud credential." |
| `ssh` | a remote Linux host | SSH key | Direct agentless remote. |
| `aws-ssm` | an EC2 instance with no inbound SSH | AWS role/key | Uses Systems Manager Session Manager. |
| `az-bastion` | an Azure VM behind Bastion | SPN (tunnel) + SSH key (inner) | Two credentials — the M:N binding case. |
| `winrm` | a Windows host | username/password (basic) or Kerberos | HTTPS; password delivered via env, never argv. |

Each channel is an independent transport implementation that can be included or
omitted at build time, so slim builds can ship without unused transports for
least-privilege deployments. The scanner selects and constructs the right
transport from the channel kind named in the binding.

## Cloud checks always use the `local` channel

> **Rule of thumb: every cloud / control-plane scan runs on the `local`
> channel.** That covers **AWS, Azure, GCP, Microsoft 365, and Kubernetes
> clusters.**

These collectors are built on **local primitives** — the scanner invokes the
provider's CLI/SDK (`aws`, `az`, `gcloud`, `kubectl`) *from the container
itself* and authenticates with the cloud credential you supplied. There is no
remote host to reach into: the "target" is an API endpoint queried locally, so
the transport is `local`. Pairing a cloud asset with `ssh`/`aws-ssm`/
`az-bastion`/`winrm` is a category error — those channels exist only for
**host** scans (a Linux or Windows machine you log into).

| Asset you're scanning | Channel | Credential the local CLI uses |
|---|---|---|
| AWS account / resource | `local` | `aws_access_key` or `aws_role` |
| Azure subscription / resource | `local` | `azure_spn` / `azure_spn_cert` |
| GCP project / resource | `local` | `gcp_sa_key` |
| Microsoft 365 tenant | `local` | `m365_delegated_refresh` |
| Kubernetes cluster | `local` | `kube_config` (or AKS/EKS cloud cred) |
| Linux host | `ssh` (or `aws-ssm` / `az-bastion`) | `ssh_key` (+ SPN for Bastion) |
| Windows host | `winrm` | `winrm_password` |

In system-ui the channel picker already restricts cloud assets to `local`, so
you normally just accept the default — but if you're driving the API directly,
set the binding's channel to `local` for any of the cloud/K8s asset types above.

## Channel ≠ binary

Channel choice is independent of the CTN set. Valid combinations include Azure
control-plane CTNs + `local` + SPN; RHEL9 host CTNs + `ssh` + SSH key; RHEL9
host CTNs + `aws-ssm` + AWS role. The engine routes each policy's required CTNs
through whichever channel the binding selected.

## Known gap (be honest in the alpha)

Five host-mode CTNs — `file_metadata`, `file_content`, `json_record`,
`tcp_listener`, `computed_values` — currently read the **scanner's** local
state rather than dispatching through the channel. For *remote* scans those five
reflect the Prooflayer host, not the target. This is tracked (architecture
Phase 2e). For local-channel scans it's correct; for SSH/SSM/Bastion scans,
prefer the channel-aware CTNs until that gap closes.

## Channel config is a cross-binary contract

The channel configuration is a serialized contract written by the server (which
dispatches scans) and read by the scanner (which executes them). Because the two
are built independently, adding a channel kind and rebuilding only one side
leaves a stale peer that fails at **runtime** when it sees a channel kind it does
not recognize, not at build time — rebuild both. See
[ops/](../ops/README.md#5-troubleshooting).
