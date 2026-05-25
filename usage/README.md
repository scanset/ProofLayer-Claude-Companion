# Usage — The Surfaces and the Core Loop

This is the end-to-end product tour: what each web surface is for, and the loop
that takes you from "I have a credential" to "here is a signed, verifiable
proof mapped to a control."

---

## The two surfaces

Both read the same evidence stream; each is scoped to one stakeholder.

### system-ui — operator / admin console
The cockpit. Talks to `/api/*` and `/api/admin/*`. You do everything
operational here:
- **Inventory** — credentials, assets, policies, asset↔policy links, schedules.
- **Discovery** — enumerate assets from a credential.
- **Scanning** — test-scan, scan-now, batch scan.
- **Evidence** — per-asset scan history, posture, drift, findings.
- **Transparency** — browse the Merkle log, verify inclusion proofs.
- **Control mapping** — see evidence roll up to framework controls.
- **Sessions** — view and revoke active sessions (single super-admin model;
  no operational-user creation in the alpha).

Auth: session token from `POST /system-ui/auth/login`, as the single
super-admin account (`super-admin` / `prooflayer`). A one-time EULA modal gates
the sign-in screen.

### CMR (Continuous Monitoring Record) — Authorizing Official / oversight
The AO's read-only oversight surface. **Headless API in the alpha** (`/cmr-api/*`,
CMR-viewer-key auth) — no UI bundle ships. It mirrors evidence for oversight:
summary rollup, asset posture history + state chains, VDR findings, control
rollup, host posture, source inspection (the exact `.esp` + CTN contract behind
any result), and on-demand proof verification (`/cmr-api/verify/{replay_hash}`
plus the signer's public key via `/cmr-api/identity/{key_id}`). 100% read-only —
the surface a consumer (an AO, a SIEM/SOAR, or an AI assistant given a key)
drives. Full walkthrough: [verification-and-oversight.md](verification-and-oversight.md).

> **Not in the alpha:** a 3PAO assessment-workflow app, SSP prose authoring,
> POA&M management, and a public trust-center are GRC authoring/workflow
> surfaces and are not part of the alpha (partner concern).

---

## The core loop

> **Step-by-step click-paths** for each action below are in
> **[workflows/](workflows/README.md)** — credentials, discovery, auto-link &
> assignment, scanning & evidence, and scheduling, as you do them in system-ui.
> The summary here is the map; the workflow pages are the turn-by-turn.

```
add credential ──► discover assets ──► link policies ──► scan ──► read evidence ──► verify proof
   (secret)          (what exists)       (what to check)  (run)     (findings)       (replay+log)
```

The three inventory concepts (keep them distinct):

| Concept | What | Lifecycle |
|---|---|---|
| **Credential** | Reusable secret (SSH key, Azure SPN, AWS role, kubeconfig, GitHub PAT). | Rotated on its own; referenced by many assets. |
| **Asset** | The thing scanned (Linux VM, AWS account, K8s cluster, M365 tenant…). Subject of an envelope. | Discovered once, tracked over time. |
| **Binding** | How to reach an asset — `(asset, channel, config, credential refs)`. | Edited when network/creds change. One asset can have several. |

### Step 1 — add a credential
system-ui → Credentials → new, or:
```bash
POST /api/inventory/credentials      # security-admin
{ "name": "demo-azure-spn", "kind": "azure_spn",
  "payload": { "kind":"azure_spn", "client_id":"...", "tenant_id":"...", "client_secret":"..." } }
```
The 12 credential kinds: `aws_access_key`, `aws_role`, `azure_spn`,
`azure_spn_cert`, `m365_delegated_refresh`, `gcp_sa_key`, `ssh_key`,
`winrm_password`, `github_pat`, `kube_config`, `local`, `network_target`.
**Each has a full reference — payload fields, required privileges, how to
obtain, rotation cadence — in [credentials/](credentials/README.md).** Credential
secrets are secured by host disk encryption plus scoped, least-privilege access
isolation, not app-layer crypto — a deliberate architecture decision.

### Step 2 — discover assets
Turn one credential into an asset list (the time-to-value step):
```bash
POST /api/inventory/discover/local          # SSH/local broadcast inventory
POST /api/inventory/discover/m365           # Microsoft Graph
POST /api/inventory/discover/k8s/local      # kubeconfig
POST /api/inventory/discover/k8s/aks        # Azure SPN + ARM id
POST /api/inventory/discover/k8s/eks        # AWS cred + cluster ARN
POST /api/inventory/discover/network        # CIDR TCP sweep
```
Discovered assets land in the asset inventory, ready to link. (You can also
create assets manually via `POST /api/inventory/assets`.)

### Step 3 — link policies to assets
A policy is **bound to an asset**; at dispatch the server injects the concrete
targets into the policy's OBJECTs.
```bash
POST /api/inventory/policies/bulk-register   # register .esp files from the tree
POST /api/inventory/asset-policies           # link one asset ↔ one policy
POST /api/inventory/asset-policies/auto-link # zero-click reconcile by target_asset_type
PUT  /api/inventory/asset-policies/{asset}/{policy}/schedule   # optional cron
```

### Step 4 — scan
```bash
POST /api/inventory/test-scan                # one asset, inline result (no persistence) — fastest sanity check
POST /api/inventory/assets/{asset_id}/scan-now
POST /api/inventory/scan-now/batch           # parallel multi-asset
```
Each dispatch resolves the credential → builds the channel → runs the policy's
CTNs through the engine → signs with the in-process scanner identity → appends
to the transparency log → persists to evidence.

### Step 5 — read the evidence
```bash
GET /api/inventory/scan-runs                              # run history
GET /api/inventory/evidence/subjects                      # per-asset latest evidence
GET /api/inventory/evidence/posture-history?asset_id=...  # posture over time
GET /api/inventory/evidence/findings                      # findings
GET /api/inventory/evidence/ctn-drift                     # per-CTN drift
```
In system-ui these power the asset detail pages: current posture
(`pass`/`fail`/`error`/`unknown`), the posture-event ledger (`first_seen` /
`drift` / `reversion` / `stable`), findings, and the CTN-level breakdown.

### Step 6 — verify the proof
This is the differentiator. For any result:
- **Replay hash** — re-run the scan; an unchanged posture reproduces the same
  `replay_hash`. `GET /verify` (and `/api/inventory/evidence/verify-hash`) look
  a hash up against the log.
- **Signature + chain** — the envelope carries the signer's cert chain back to
  the root CA.
- **Transparency log** — `GET /api/transparency/*` exposes the tree summary,
  entries, inclusion proofs, and checkpoints; the UI verifies proofs
  client-side. CMR exposes the same under `/cmr-api/transparency/*`.

> Honest framing for evaluators: the alpha's log is **tamper-evident** — a
> single operator's append-only Merkle log with signed checkpoints. It proves
> non-repudiation of issuance. It does *not* yet have consistency proofs or
> external witnessing, so don't claim "the operator can't rewrite history." The
> primitives to close that gap exist; it's scoped out of the alpha.

---

## What to actually click through in an evaluation

1. Accept the EULA and log in to system-ui as `super-admin` / `prooflayer`.
2. Add a credential for whatever you have (or skip — use the local channel).
3. Discover or hand-add an asset.
4. Link a policy (or auto-link), then **Test Scan** it.
5. Open the asset's evidence: read the posture, the findings, the CTN results.
6. Open the **Transparency** page: find your scan's log entry, verify its
   inclusion proof.
7. With a **CMR viewer key**, read the same evidence through `/cmr-api/*` and
   recompute the verdict on demand (`/cmr-api/verify/{replay_hash}`) — the
   oversight lens over the exact proof you just produced.

No targets handy? [test_fixtures/](../test_fixtures/README.md) deploys real
ones with Terraform, or scan the container host itself over the local channel.
