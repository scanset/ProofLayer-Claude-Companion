# Prooflayer Alpha — Evaluation Guide

Welcome. This guide gets you from a fresh **Prooflayer alpha-release container** to
a working evaluation: a logged-in admin console, a scan you ran yourself, and
a signed, control-mapped, transparency-logged piece of evidence you can verify.

If you're a human, read on. If you're Claude, start at [`CLAUDE.md`](CLAUDE.md).

### Using the Claude companion

This guide is also a **Claude companion**: open this folder in
[Claude Code](https://claude.com/claude-code) (or the Claude desktop/IDE
extension) and just ask. [`CLAUDE.md`](CLAUDE.md) is the entry point Claude
reads first — it routes any question to the right page so you don't have to know
the layout. Ask the way you'd ask a teammate:

- *"Where do I start?"* → it points you at [quickstart.md](quickstart.md).
- *"How do I add an Azure credential?"* → the right
  [credentials](usage/credentials/README.md) page.
- *"What is the replay hash?"* / *"What does CTN mean?"* → a
  [glossary](glossary.md) answer.
- *"How do I set up the container?"* → [setup/](setup/README.md).
- *"What data leaves the container?"* → [data-egress.md](data-egress.md).

Everything it needs is in this folder — it's self-contained, so answers stay
grounded in the guide rather than guessed.

> **Open source.** The ESP engine — the language + execution engine the scanner
> runs — is open-source at <https://github.com/scanset/Endpoint-State-Policy>.
> The **Agent-SDK** (<https://github.com/scanset/Agent-SDK>) is the public repo
> for developing CTN contracts and testing ESP policies.

---

## What is Prooflayer?

Prooflayer is an **agentless continuous-compliance platform**. It produces
cryptographically verifiable compliance evidence that a security team, an
Authorizing Official, and downstream consumers (a 3PAO, a SIEM/SOAR, a GRC tool)
can each verify independently — replacing static PDFs and spreadsheets with a
live, auditable trust chain.

A scan in Prooflayer is not just a finding — it's a **proof**:

| Property | What it means |
|---|---|
| **Signed envelope** | Every scan result (`AssessorPackage`) is signed by a key issued from Prooflayer's own Issuing Authority. |
| **Replay hash** | A deterministic, identity-free SHA-256 over the normalized scan inputs. Same posture → same hash. Drift detection and tamper detection in one field. |
| **Transparency log** | Every signing identity is appended to an append-only Merkle tree with periodic signed checkpoints. The chain is verifiable. |
| **Control mapping** | Each policy maps to compliance controls (FedRAMP 20x KSI, NIST 800-53, NIST 800-171 — CMMC maps onto 800-171), so evidence rolls up to a framework. |

**Agentless** means a central server reaches each target over a pluggable
**channel** — `local`, `ssh`, `aws-ssm`, `az-bastion`, `winrm` — runs
declarative **ESP policies** through a built-in engine, and signs + logs the
result. Nothing is installed on the scanned endpoint.

> Positioning: *Prooflayer makes proofs.* The moat is the
> proof contract — signed, replayable, transparency-logged, control-mapped —
> which downstream systems consume rather than rebuild.

---

## The two surfaces

Both read from the same evidence stream; each serves a different stakeholder.

| Surface | Stakeholder | Auth | API prefix | Status in alpha |
|---|---|---|---|---|
| **system-ui** | Operator / SOC / admin | login (session token) | `/api/*`, `/api/admin/*` | Browser app |
| **CMR (Continuous Monitoring Record)** | Authorizing Official / oversight | API key (CMR viewer) | `/cmr-api/*` | **Headless API only** in alpha |

GRC *authoring/workflow* surfaces (3PAO assessment workflow, SSP prose authoring,
POA&M, a public trust-center) are **not in the alpha** — Prooflayer is the
evidence engine; those are a partner concern. Details and an end-to-end
walkthrough are in [usage/README.md](usage/README.md).

---

## Guide map

| Section | What's in it |
|---|---|
| [quickstart.md](quickstart.md) | **Start here.** The end-to-end guided loop: log in → deploy a fixture → add credential → discover → auto-link policies → assign channel+credential → scan → verify. |
| [glossary.md](glossary.md) | Every term in one place — canonical one-liners with a pointer to the deep page. The fastest way to orient. |
| [setup/](setup/README.md) | Pull-and-run the evaluation container: `docker pull` + `docker run`, the two ports, the EULA gate, and the default login. It provisions itself on first launch — nothing to build or configure. |
| [components/](components/README.md) | Conceptual reference — one page per part of the system (replay hash, transparency log, PKI/identity, evidence, inventory, channels, discovery, posture, control mapping, VDR, findings & remediation, surfaces, and pathfinder). ESP itself lives in `esp/`. |
| [usage/](usage/README.md) | The two surfaces explained, the core loop, and **[workflows/](usage/workflows/README.md)** — step-by-step operator click-paths (credentials, discovery, auto-link & policy assignment, scanning & evidence, scheduling). |
| [esp/](esp/README.md) | The full ESP reference (multi-page): how the engine works, the language, evaluation & outcomes, META & control mapping, the envelope, writing policies, **injection & scoped injection**, the `assessor` CLI, and errors/gotchas. |
| [api/](api/README.md) | HTTP API reference: the route map, auth models, and copy-paste `curl` examples. |
| [admin/](admin/README.md) | Administrative tasks **inside** Prooflayer: login & sessions, API keys (incl. the CMR viewer key) & webhooks, credential governance, policy registry & scheduling. |
| [ops/](ops/README.md) | Operating the **container/host**: processes, PKI on disk, logs, backup/restore, troubleshooting, account recovery. (The internal datastore is sealed — not operator-facing.) |
| [data-egress.md](data-egress.md) | **What leaves the container.** Outbound connections, the inbound surfaces, what never leaves on its own, and an egress checklist for a locked-down eval. |
| [test_fixtures/](test_fixtures/README.md) | Terraform-deployable scan targets + credentials (with [credentials/](test_fixtures/credentials/README.md) and [infrastructure/](test_fixtures/infrastructure/README.md) subfolders) plus the zero-setup local-channel quickstart. |

---

## The fastest possible evaluation (≈5 minutes)

> Want the **full guided loop** (real target → credential → discovery →
> auto-link → channel → scan → verify)? See **[quickstart.md](quickstart.md)**.
> The 5-minute version below is the no-cloud local-channel path.

1. Run the container (see [setup/](setup/README.md)).
2. Open the system-ui, accept the EULA on the sign-in screen, and log in as
   `super-admin` / `prooflayer`.
3. **Test Scan the container host over the `local` channel** — no cloud
   credentials required. Use the system-ui **Test Scan** page (or
   `POST /api/inventory/test-scan`); it scans the host the container runs on.
4. Read the result: per-policy outcomes, a `replay_hash`, and a `signature`
   block — that is a proof. It's signed by the issuing authority, appended to
   the transparency log, and persisted to evidence.
5. Open the **Transparency** page, find your scan's entry, and verify its
   inclusion proof — the full chain, end to end. See [usage/](usage/README.md).

---

## Alpha scope — read this before you judge it

The alpha is an **evaluation build**, not a production deployment:

- **Plain HTTP** — nginx does not terminate TLS in the eval container, so the
  browser connection is unencrypted (no certificate, no warning). The
  self-signed PKI generated at first boot exists to sign scan envelopes and the
  transparency log, not the browser connection.
- **Fixed default login** (`super-admin` / `prooflayer`). The alpha uses a
  single super-admin model — no password change and no user creation; the
  credentials just work. A one-time EULA modal gates the sign-in screen.
- **Non-FIPS** dev build. Production links FIPS 140-3 validated OpenSSL.
- **Single container**, one sealed internal datastore, no HA.
- **Transparency log is tamper-evident, not tamper-proof** — it's a single
  operator's append-only Merkle log; consistency proofs and external
  witnessing are not in the alpha.
- **CMR/AO is headless** (API only). AI-assisted and bring-your-own-account
  workflows are deferred.

What it *does* demonstrate end-to-end: agentless scanning over real channels,
the signed/replayable/logged proof contract, control mapping to real
frameworks, and the shared evidence stream behind both the operator and
oversight views.
