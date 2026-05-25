# Quick Start — Zero to a Signed Proof

The fastest guided path from a fresh container to a **signed, control-mapped,
verifiable scan result**. Each step links to the deeper page if you want detail.

> The 5-minute, no-cloud version is in the [README](README.md#the-fastest-possible-evaluation-5-minutes)
> (run a local-channel scan, read the envelope). This page is the **full
> cloud-style loop**: real target → credential → discovery → policies → channel →
> scan → verify.

---

## Run the container

The alpha ships as a single all-in-one image. Pull it and start it:

```bash
docker pull scanset/prooflayer-alpha-v0_1:0.1-alpha

# -p 8080:80   → operator UI + API
# -p 9090:8081 → CMR read-only oversight API (optional)
docker run -d --name prooflayer-alpha -p 8080:80 -p 9090:8081 \
  scanset/prooflayer-alpha-v0_1:0.1-alpha
```

Then open **http://localhost:8080** in a browser — that's the operator
(system-ui) console. The eval image serves plain HTTP, so there's no
self-signed-cert warning. The read-only CMR oversight API (for an AO or an AI
with a key) is on **http://localhost:9090** under `/cmr-api/*`.

First launch provisions the PKI, the internal datastore, and the seed content
automatically — give it a few seconds after the container starts, then continue.
Full container details (ports, login, what it manages for you) are in
[setup/](setup/README.md).

---

## 0. Log in

Browse to **http://localhost:8080**, **accept the EULA** on the sign-in screen,
and log in:

- **Username:** `super-admin`
- **Password:** `prooflayer`

The alpha is a single super-admin model — those credentials just work (no
password change, no user creation). See [setup/](setup/README.md#3-logging-in-first-run).

## 1. Get something to scan (test fixtures)

You need a real target. Two options:

- **No cloud (start here):** scan the container host itself over the `local`
  channel — skip to step 5 using the auto-seeded `local` credential. See
  [test_fixtures/ Tier 0](test_fixtures/README.md).
- **Cloud demo:** deploy a purpose-built target with the bundled **Terraform
  fixtures**. Each is two parts:
  1. a **credential** fixture — `azure-spn` (yields the Azure credential kinds)
     or `aws-iam` (role/key), least-privilege by design
     ([test_fixtures/credentials/](test_fixtures/credentials/README.md)); then
  2. a **target** fixture — a cloud-resource target with deliberate drift
     (`aws-target` / `azure-target`, scanned over `local`), or **multi-OS hosts**
     (`host-targets` / `azure-host-targets` — Ubuntu / Rocky-or-RHEL 9 / Windows,
     scanned over `ssh`/`winrm`)
     ([test_fixtures/infrastructure/](test_fixtures/infrastructure/README.md)).

  > Terraform fixtures create **billable** resources — `terraform destroy` when
  > done.

## 2. Insert the credential

Add the secret Prooflayer will authenticate as — system-ui → **Credentials → New**
(or `POST /api/inventory/credentials`). Pick the kind that matches your fixture
(`azure_spn`, `aws_access_key`/`aws_role`, `kube_config`, `ssh_key`, …). Per-kind
fields and how-to-obtain: [usage/credentials/](usage/credentials/README.md) and
the [credentials workflow](usage/workflows/credentials.md).

## 3. Run discovery → assets populate and link themselves

Point discovery at the credential (system-ui → **Discover**, or
`POST /api/inventory/discover/...`). Prooflayer enumerates everything that
credential can see and **populates the asset inventory automatically**. It also
**links the assets to each other** — the discovered topology (a subscription
*contains* a resource group, a cluster *contains* a node) is recorded as the
asset graph, so the relationships are built for you. See the
[discovery workflow](usage/workflows/discovery.md).

## 4. Auto-link policies

Click **Auto-link** (or `POST /api/inventory/asset-policies/auto-link`).
Prooflayer reconciles the registered policies against your assets by type and
binds the right policies to the right assets — no hand-matching. Confirm the
scoping on the **Inventory Assignments** view (this is *what gets checked*). See
the [auto-link & assignment workflow](usage/workflows/auto-link-and-assignment.md).

## 5. Assign a scan channel + credential to the assets

This is *how the scanner reaches each asset* — distinct from step 4 (which is
*what to check*). Open an asset's **Edit** drawer (from the Assets page or asset
detail) and set:

- **Scan channel** — how to reach it. The picker offers only the channels valid
  for that asset type:
  - **Cloud control-plane assets** (Azure/AWS/M365/GCP resources) → `local`
    (the scanner queries the provider's API/CLI using your cloud credential).
    This is usually the default.
  - **Linux hosts** → `ssh` (with an SSH-key credential), or `aws-ssm` /
    `az-bastion` for hosts with no inbound SSH.
  - **Windows hosts** → `winrm`.
  - **Kubernetes** → handled via the kubeconfig/cluster credential.
- **Credential** — which stored credential to use over that channel.

Often the credential you discovered with is already the right one to scan with;
this step is where you confirm or override it (and where host assets get their
SSH key). The five channels and when to use each:
[components/channels.md](components/channels.md).

> **Heads-up (alpha gap):** for *remote* host scans, five host-mode checks still
> read the scanner's own state rather than the target — prefer the channel-aware
> checks until that closes. Detail in [channels.md](components/channels.md#known-gap-be-honest-in-the-alpha).

## 6. Scan

Trigger it — system-ui → **Scan now** (or `POST /api/inventory/assets/{id}/scan-now`,
or `…/scan-now/batch` for many at once). For the very first sanity check,
**Test Scan** (`POST /api/inventory/test-scan`) runs one asset and returns the
result inline without persisting.

Each dispatch resolves the credential → builds the channel → runs the policy's
checks → signs the result with the scanner identity → appends to the
transparency log → persists the evidence. Policies **fan out** at this point:
one policy bound to a parent (a subscription, a cluster) scans every matching
resource under it via [scoped injection](esp/injection-and-scoped-injection.md).
Full detail: [scan & read evidence](usage/workflows/scanning-and-evidence.md).

## 7. Read the proof and verify it

- **Posture & findings** — open the asset: current posture
  (`pass`/`fail`/`error`/`unknown`), the failing checks with reproduction
  detail, and the [state chain](components/state-chain.md) of how posture
  evolved. ([Understanding evidence](components/understanding-evidence.md);
  [findings](components/findings-and-remediation.md).)
- **Verify** — re-run an unchanged target and it reproduces the same replay
  hash; check the transparency inclusion proof; or hand a **CMR viewer key** to
  an AO / the AI to recompute the verdict on demand. See
  [verification & oversight](usage/verification-and-oversight.md).

---

## The whole loop, at a glance

```
log in ─▶ deploy a fixture ─▶ add credential ─▶ discover (assets + their links
   │                                              auto-populate)
   │                                                     │
   ▼                                                     ▼
verify ◀─ scan ◀─ assign channel + credential ◀─ auto-link policies
proof     (run)   (how to reach each asset)       (what to check)
```

Two assignments, don't conflate them: **auto-link policies** = *what to check*;
**channel + credential** = *how to reach it*. Both must be set before a scan
produces meaningful evidence.

Next: the [usage tour](usage/README.md) and the per-step
[workflows](usage/workflows/README.md).

---

## Verified a proof — like what you see?

That `matches: true` is the core of Prooflayer: posture re-derived from evidence,
mapped to controls, with a transparency-log leaf. If the eval lands — or you're
weighing a **pilot, production deployment, or coverage for a framework or asset
type you need** (FedRAMP 20x KSI, NIST 800-53 / 800-171, CMMC, or a platform not
yet covered) — reach out: **[contact@scanset.io](mailto:contact@scanset.io)**.
Telling us *what assets and frameworks matter most in your environment* is the
single most useful thing at this stage. (Deeper next steps:
[test_fixtures/suggestions.md](test_fixtures/suggestions.md).)
