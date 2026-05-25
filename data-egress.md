# Data Egress — What Leaves the Container

A straight answer to the question a security reviewer asks first: **what network
connections does this container make, and what data crosses its boundary?**

> **Bottom line.** The container makes **no outbound connection you didn't ask
> for.** There is no telemetry, no analytics, no phone-home, no license check,
> and no registration callout. Every outbound connection is either (a) a scan or
> discovery you initiated, reaching a target *you* specified with a credential
> *you* supplied, or (b) a webhook *you* configured. Your evidence, transparency
> log, and credentials stay inside the container unless you explicitly pull them
> out through the API or wire them to a webhook.

This makes the alpha suitable for a network-restricted or air-gapped
evaluation: run it with **zero egress** and you can still scan the container
host itself over the `local` channel end-to-end.

---

## Outbound — connections the container originates

All of these are **operator-initiated** and go **only** to endpoints you
configure. None happen on their own.

| Class | When it happens | Destination | What's sent | What's *not* sent |
|---|---|---|---|---|
| **Host scan** (`ssh`, `winrm`) | You run a scan/discovery against a host | The host's address + port you set on the binding | Authentication, then read-only collection commands | No scanned data leaves — results come *back* into the container |
| **Cloud control-plane scan** | You scan/discover a cloud asset | The provider's API/CLI endpoints (AWS, Azure/ARM, GCP, Microsoft Graph) | The credential + read-only API calls | Same — responses land in the container only |
| **Credential token exchange** | Any cloud auth | The provider's token endpoint (AWS STS, Microsoft Entra, Google OAuth) | Your client/role credential, to obtain a short-lived token | — |
| **Kubernetes scan** | You scan a cluster | The cluster's apiserver (and, for AKS/EKS, the cloud's token endpoint) | kubeconfig/SA identity + read-only API calls | — |
| **Network sweep discovery** | You run a CIDR sweep | The exact CIDR/ports you enter | TCP connect probes only | No payloads; reachability only — see [components/network-sweep-discovery.md](components/network-sweep-discovery.md) |
| **Webhooks** | *Only if* you configure outbound webhook endpoints | The URL(s) you register | Event notifications (e.g. scan completion) | Off by default; you choose the URL and what subscribes |

Channels and what each reaches:
[components/channels.md](components/channels.md). Discovery sources:
[usage/workflows/discovery.md](usage/workflows/discovery.md).

---

## Inbound — connections others make *to* the container

| Port | Who connects | Auth |
|---|---|---|
| **`:80`** (mapped to e.g. `8080`) | The operator, in a browser | Session login |
| **`:8081`** (mapped to e.g. `9090`) | A consumer you grant a key — an AO, a SIEM/SOAR, or an AI assistant | CMR viewer **API key**, read-only |

The CMR surface is a **pull** model: a consumer you've issued a key to reads
evidence on demand (`/cmr-api/*`). Nothing is pushed unless *you* wired a webhook
(above). Issue/scope keys in [admin/](admin/README.md#2-keys--webhooks-apiadmin);
the consumer's view is [usage/verification-and-oversight.md](usage/verification-and-oversight.md).

---

## What never leaves on its own

Evidence envelopes, the transparency log, credential secrets, replay hashes, the
control catalog, and the vulnerability catalog all live on the container's
volume. They leave the boundary **only** by an action you take:

- a consumer **pulls** them through the key-gated CMR read API, or
- a **webhook you configured** pushes an event notification, or
- you copy them out yourself (e.g. an API export, or backing up the volume —
  see [ops/ §4](ops/README.md#4-backup--restore)).

There is no background sync, no vendor callback, and no usage reporting in the
alpha.

---

## Egress checklist for a locked-down eval

| You want to… | Egress you must allow |
|---|---|
| Evaluate with **zero network** | None — pull the image, then scan the container host over `local`. |
| Scan **remote Linux/Windows hosts** | Outbound `ssh` (22) / `winrm` (5985/5986) to those hosts only. |
| Scan **AWS / Azure / GCP / M365** | HTTPS to that provider's API + token endpoints only. |
| Scan **Kubernetes** | HTTPS to the apiserver (+ the cloud token endpoint for AKS/EKS). |
| Receive **webhook notifications** | Outbound to the URL you register. |

Pulling the image itself needs egress to the registry once; after that the
container runs without it (modulo whatever targets you choose to scan).
