# Inventory — Credential, Asset, Channel Binding

**Status: built (credentials + assets + linking; bindings table maturing).**

## The three-concept model

Prooflayer's inventory has **three** distinct concepts, not two. Separating the
asset from how you reach it is what enables multi-channel assets, failover, and
credential rotation without touching the asset record.

| Concept | What it is | Lifecycle |
|---|---|---|
| **Credential** | Reusable secret material — an SSH key, an Azure SPN, an AWS role, a WinRM password. A connection profile, not a target. | Rotated on its own cadence; referenced by many assets. |
| **Asset** | The thing being scanned — a Linux VM, an AWS account, a K8s cluster, an M365 tenant. The subject of an envelope. | Discovered once, persists, tracks identity over time. |
| **Channel binding** | How to reach a specific asset — the asset, a channel kind, its config, and the credential references it needs. | Edited when network/creds change. One asset can have several (primary SSM, fallback SSH). |

Why three: one SSH key rotates and 40 VMs keep working (the key is its own
record); one asset is reachable by SSM-primary + SSH-fallback (a single asset can
carry several bindings); one bastion binding can reference two credentials — the
tunnel SPN *and* the inner SSH key (a binding can reference many credentials).

## Credentials

Stored as **least-privilege-scoped plaintext** secret material. There is no
app-layer encryption — security comes from host disk encryption, least-privilege
access scoping that separates who may write a credential from who may read it on
the dispatch path, and loopback-only reachability (a deliberate architecture
decision). The 12 kinds are
`aws_access_key`, `aws_role`, `azure_spn`, `azure_spn_cert`,
`m365_delegated_refresh`, `gcp_sa_key`, `ssh_key`, `winrm_password`,
`github_pat`, `kube_config`, `local`, `network_target` — each documented in
[../usage/credentials/](../usage/credentials/README.md). Non-secret display hints
(region, tenant) are kept separately so they are safe to show in the UI.

There are **no ambient-credential variants** — every account, including the one
Prooflayer runs in, has its own explicit record. The VM instance role is
bootstrap-only.

## Assets

Discovered (see [discovery.md](discovery.md)) or hand-created. Each carries an
asset type, a provider id, free-form metadata, graph edges to its parents (which
injection walks), and its current posture with the time it was last updated.
Assets are soft-deleted, not hard-deleted.

## Linking is how scanning is driven

A policy is **bound to an asset** with a status of active, paused, or archived.
That binding — not the policy text — determines scope; at dispatch the server
injects the concrete targets (see
[injection-and-scoped-injection.md](../esp/injection-and-scoped-injection.md)). Each
dispatch records the full input tuple — the asset, policy, credential, the policy
content fingerprint, the scanner identity, the trigger, and any parent run — so
any run can be **replayed** deterministically.

Operate all of this from [admin/](../admin/README.md#3-credential-governance-apiinventorycredentials)
and [usage/](../usage/README.md).
