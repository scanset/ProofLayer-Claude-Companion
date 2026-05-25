# Components — What Each Part of Prooflayer Does

A conceptual reference: one page per part of the system, explaining *what it is*
and *why it exists*. Read these to understand the machine; read
[usage/](../usage/README.md) to operate it and [esp/](../esp/README.md) to
author for it.

> **Built vs planned.** Pages are labeled. Most components are implemented in
> the alpha; where a feature is partial (e.g. **Pathfinder**'s attack-path layer
> is roadmap) the page says so.
> When a page describes behavior, it reflects the active stack (`prooflayer-2`,
> `assessor-core`, `channels`) pinned to ESP engine `@v2.0.0`.

## The proof contract (the differentiator)

| Page | One-liner |
|---|---|
| [replay-hash.md](replay-hash.md) | Deterministic, identity-free hash of a scan. Same posture → same hash. Drift + tamper detection in one field. |
| → [replay-hash-canonical-spec.md](replay-hash-canonical-spec.md) | **Deep dive.** The byte-exact canonical manifest, the `H(x)` primitive, and the v1/v2 rollups — the verifier contract. |
| [transparency-log.md](transparency-log.md) | Append-only Merkle log of every signing identity, with signed checkpoints. Tamper-evident. |
| → [transparency-and-verifiable-evidence.md](transparency-and-verifiable-evidence.md) | **Deep dive.** The three proof artifacts, leaf/proof/checkpoint structure, end-to-end verification, and the honest claim hierarchy. |
| [understanding-evidence.md](understanding-evidence.md) | **Start here.** The anatomy of a proof — what a piece of evidence is, why it's a proof not a finding, and how to read one. |
| [pki-and-identity.md](pki-and-identity.md) | The Issuing Authority, the in-process scanner identity, and how envelopes get signed. |
| [evidence-and-ingest.md](evidence-and-ingest.md) | The `AssessorPackage` envelope and the one ingest path everything flows through. |

## What gets scanned, and how

| Page | One-liner |
|---|---|
| [inventory.md](inventory.md) | The three-concept model: credential, asset, channel binding. |
| [channels.md](channels.md) | The transport abstraction — local / SSH / AWS SSM / Azure Bastion / WinRM. |
| [discovery.md](discovery.md) | Discovery-as-policy: enumerate assets from a credential. |
| → [network-sweep-discovery.md](network-sweep-discovery.md) | **Deep dive.** The CIDR TCP-sweep probe: privilege model, reachability, container/WSL2 limits, operational notes. |

> **ESP itself lives in [../esp/](../esp/README.md).** The engine + CTN primitives,
> the policy language, and injection / scoped injection are documented there in
> depth — see [../esp/how-esp-works.md](../esp/how-esp-works.md) (engine + CTNs)
> and [../esp/injection-and-scoped-injection.md](../esp/injection-and-scoped-injection.md)
> (one policy → N assets).

## State, posture, and rollup

| Page | One-liner |
|---|---|
| [posture-and-drift.md](posture-and-drift.md) | Posture-as-state, the posture-event ledger, the three word-senses of "drift". |
| [state-chain.md](state-chain.md) | The per-(asset, policy) timeline of signed scans, hash-linked — how an asset's posture got to where it is. |
| [ssp-and-control-mapping.md](ssp-and-control-mapping.md) | How evidence auto-rolls-up to framework controls (and where SSP authoring is *not* in scope). |
| [vulnerability-vdr.md](vulnerability-vdr.md) | The CVE catalog and the Vulnerability Disclosure Report findings surface. |

## Surfaces & projections

| Page | One-liner |
|---|---|
| [surfaces.md](surfaces.md) | The two stakeholder views — operator (system-ui) and AO oversight (CMR) — over one evidence stream. |
| [pathfinder.md](pathfinder.md) | **Built (V2).** A focus-asset risk-neighborhood graph over inventory + findings; attack-path finding is roadmap. |
