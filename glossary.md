# Glossary — Prooflayer Terminology

Canonical one-line definitions for every term this guide uses, with a pointer to
the page that goes deep. When a term is ambiguous (CTN, "drift") the canonical
sense is stated here. Alphabetical.

| Term | Definition | More |
|---|---|---|
| **Agentless** | Nothing is installed on the scanned endpoint. A central server reaches each target over a **channel**, runs the policy, and signs the result. The alpha is agentless-only — there is no agent/enrollment deployment mode. | [README](README.md) |
| **AO (Authorizing Official)** | The oversight stakeholder who accepts risk. In the alpha, the AO reads evidence through the **CMR** surface with a viewer key. | [components/surfaces.md](components/surfaces.md) |
| **Asset** | The thing scanned — a Linux/Windows host, a cloud account/resource, a K8s cluster, an M365 tenant. The subject an envelope is about. | [components/inventory.md](components/inventory.md) |
| **Asset graph** | The discovered topology linking assets (a subscription *contains* a resource group; a cluster *contains* a node). Drives scoped injection's fan-out. | [components/discovery.md](components/discovery.md) |
| **AssessorPackage** | The signed scan-result **envelope** the scanner emits and the server ingests. Carries observations, outcomes, the replay hash, and the signature block. | [esp/the-envelope.md](esp/the-envelope.md) |
| **Binding** | An **asset↔policy link** — the record that says "check this policy on this asset." Carries a status (active / pending OBJECT add / paused / archived) and an optional schedule. Distinct from a *channel binding* (how to reach an asset). | [usage/workflows/auto-link-and-assignment.md](usage/workflows/auto-link-and-assignment.md) |
| **Channel** | The transport the scanner uses to reach a target: `local`, `ssh`, `aws-ssm`, `az-bastion`, `winrm`. Chosen per asset; distinct from the policy bound to it. | [components/channels.md](components/channels.md) |
| **Checkpoint** | A periodically committed, **signed** root of the transparency tree. Anchors the log so any entry's inclusion can be verified against a published root. | [components/transparency-log.md](components/transparency-log.md) |
| **CMR (Continuous Monitoring Record)** | The read-only oversight surface (`/cmr-api/*`), key-gated, **headless in the alpha** (no UI bundle). The AO/SIEM/AI lens over the same evidence stream. | [usage/verification-and-oversight.md](usage/verification-and-oversight.md) |
| **CMMC** | DoD's Cybersecurity Maturity Model Certification. Prooflayer maps it onto **NIST 800-171** controls rather than treating it as a separate catalog. | [components/ssp-and-control-mapping.md](components/ssp-and-control-mapping.md) |
| **Control mapping** | Each policy declares the compliance controls it demonstrates; signed evidence auto-rolls-up to those framework controls at query time (no manual linking). | [esp/meta-and-control-mapping.md](esp/meta-and-control-mapping.md) |
| **CRI (Criterion)** | An ESP construct: a named check that ties an OBJECT to a STATE via a TEST and yields one outcome. | [esp/language-reference.md](esp/language-reference.md) |
| **Credential** | A reusable secret the scanner authenticates with (SSH key, Azure SPN, AWS role, kubeconfig, GitHub PAT, …). 12 kinds. Referenced by many assets; rotated on its own. | [usage/credentials/](usage/credentials/README.md) |
| **CTN** | **Criterion Type Node** (the engine's term; the guide also calls it a *Compliance Target Node*) — one of ~80 collection primitives the engine knows how to evaluate (a file, a registry key, a cloud API object…). Each has a **contract** doc. | [esp/how-esp-works.md](esp/how-esp-works.md) |
| **Datastore (internal)** | The container's sealed internal store for evidence, the transparency log, and catalogs. Auto-provisioned, loopback-only, not operator-facing — black-boxed by design. | [setup/](setup/README.md) |
| **Discovery** | Turning one credential into an asset inventory — enumerating what exists (and its topology) so you can link policies to it. | [components/discovery.md](components/discovery.md) |
| **Drift** | Three senses, kept distinct: (1) **posture drift** — an asset's outcome changed between scans; (2) **CTN drift** — a specific check's result changed; (3) *configuration* drift on the target itself. The posture-event ledger records (1). | [components/posture-and-drift.md](components/posture-and-drift.md) |
| **Egress** | What network connections the container originates. None happen on their own — only scans/discovery/webhooks you configure. | [data-egress.md](data-egress.md) |
| **ESP (Endpoint State Policy)** | The declarative policy language + execution engine the scanner runs. Open-source. Policies are `.esp` files. | [esp/README.md](esp/README.md) |
| **`esp_assessor`** | The scanner CLI binary. The server dispatches it over a channel; you can also run it by hand for local testing. | [esp/assessor-cli.md](esp/assessor-cli.md) |
| **EULA gate** | A one-time end-user-license modal that gates the sign-in screen; acceptance is stored per-version in the browser. | [setup/](setup/README.md#3-logging-in-first-run) |
| **Evidence** | A persisted, signed scan result — the *proof*, not just a finding. Read per-asset as posture, findings, and CTN results. | [components/understanding-evidence.md](components/understanding-evidence.md) |
| **FedRAMP 20x** | The modernized FedRAMP track built on machine-verifiable **KSIs**. One of the seeded frameworks. | [components/ssp-and-control-mapping.md](components/ssp-and-control-mapping.md) |
| **Finding** | A failed (or error/unknown) check surfaced for action, with reproduction detail. Findings are a *view* over evidence, not a separate source of truth. | [components/findings-and-remediation.md](components/findings-and-remediation.md) |
| **IA (Issuing Authority)** | The intermediate CA (loaded at server start) that signs the in-memory scanner and log-signing identities. Sits under the offline-capable root CA. | [components/pki-and-identity.md](components/pki-and-identity.md) |
| **Inclusion proof** | The Merkle path showing a given entry is in the transparency tree under a published root. Verified client-side. | [components/transparency-and-verifiable-evidence.md](components/transparency-and-verifiable-evidence.md) |
| **Injection** | At dispatch, the server fills a policy's placeholder OBJECT with the concrete target before running it. | [esp/injection-and-scoped-injection.md](esp/injection-and-scoped-injection.md) |
| **KSI (Key Security Indicator)** | FedRAMP 20x's machine-checkable security indicators. (If a source expands the acronym to anything else, it's wrong.) | [components/ssp-and-control-mapping.md](components/ssp-and-control-mapping.md) |
| **Outcome** | A check's verdict: **`pass` / `fail` / `error` / `unknown`**. `unknown` is a real 4th variant — don't remap it (that breaks replay-hash integrity). | [esp/evaluation-and-outcomes.md](esp/evaluation-and-outcomes.md) |
| **Pathfinder** | A focus-asset **risk-neighborhood graph** over inventory + findings (built, V2). Full attack-path finding is roadmap. | [components/pathfinder.md](components/pathfinder.md) |
| **PKI** | Prooflayer's own certificate hierarchy (root CA → IA → in-memory scanner + log-signing certs). Makes a scan result a *proof* by chaining its signer to a known root. | [components/pki-and-identity.md](components/pki-and-identity.md) |
| **Posture** | The current compliance **state** of an asset (per policy/CTN), modeled as state rather than as a pile of past scan records — the differentiator. | [components/posture-and-drift.md](components/posture-and-drift.md) |
| **Posture-event ledger** | The append-only record of posture transitions per (asset, policy): `first_seen` / `drift` / `reversion` / `stable`. | [components/posture-and-drift.md](components/posture-and-drift.md) |
| **Proof** | A scan result that is signed, replay-hashed, transparency-logged, and control-mapped — independently verifiable. The product's category line: *Wiz makes findings; Prooflayer makes proofs.* | [components/understanding-evidence.md](components/understanding-evidence.md) |
| **Replay hash** | A deterministic, identity-free SHA-256 over the normalized scan inputs. Same posture → same hash. Drift + tamper detection in one field; re-running an unchanged target reproduces it. | [components/replay-hash.md](components/replay-hash.md) · [spec](components/replay-hash-canonical-spec.md) |
| **Scanner identity** | The in-process workload cert (SAN `esp://prooflayer/<deployment>/scanner`) the server signs envelopes with, logged to the transparency log at boot. | [components/pki-and-identity.md](components/pki-and-identity.md) |
| **Scoped injection** | One policy bound to a parent asset fans out at dispatch to **every matching child resource** (walk → project → fill → splice), with a per-resource verdict each. | [esp/injection-and-scoped-injection.md](esp/injection-and-scoped-injection.md) |
| **SET / SET_REF** | ESP constructs for a set of objects and a reference to one — the seam scoped injection writes resolved resources into. | [esp/language-reference.md](esp/language-reference.md) |
| **State chain** | The hash-linked, per-(asset, policy) timeline of signed scans — how an asset's posture got to where it is. | [components/state-chain.md](components/state-chain.md) |
| **Subject** | The asset an envelope's attestation is *about* (vs the *executor* that produced it — the scanner identity or, for single-host CTNs, the target host). | [components/evidence-and-ingest.md](components/evidence-and-ingest.md) |
| **`target_asset_type`** | A policy's optional META hint for which asset type it expects to be linked under. Drives the link picker + auto-link; **not** a category. | [esp/meta-and-control-mapping.md](esp/meta-and-control-mapping.md) |
| **system-ui** | The operator/admin browser console (`/api/*`). Inventory, discovery, scanning, evidence, transparency, control mapping. | [usage/README.md](usage/README.md) |
| **Transparency log** | An append-only RFC-6962-style Merkle log of every signing identity, with signed checkpoints. **Tamper-evident**, not tamper-proof (single operator; no consistency proofs/witnessing yet). | [components/transparency-log.md](components/transparency-log.md) |
| **VDR (Vulnerability Disclosure Report)** | The vulnerability findings surface over the seeded CVE catalog, with remediation decisions. | [components/vulnerability-vdr.md](components/vulnerability-vdr.md) |

---

> Naming conventions in this guide: **CTN** = Criterion Type Node (engine) /
> Compliance Target Node (product); **CMR** = Continuous Monitoring Record (the
> oversight surface, formerly AO/SSDR); **proof** is preferred over "finding"
> for a signed result. If a term here disagrees with a page, this glossary is
> the canonical short form — open an issue against the deep page.
