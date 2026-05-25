# How ESP Works

The mental model: what the engine is, the pipeline a policy travels, and the
design principles that make a scan into a *proof*. Concepts only — not engine
internals.

> Reflects the normative ESP language specification (bundled in [spec/](spec/README.md)); the engine is pinned at v2.0.0 across Prooflayer's active stack. The engine is **open-source**: <https://github.com/scanset/Endpoint-State-Policy> (contract development + ESP testing: <https://github.com/scanset/Agent-SDK>).

---

## 1. What ESP is

**ESP (Endpoint State Policy)** is a declarative DSL for compliance checks. A
policy describes **what should be true** about a target's state — not *how* to
go check it. The "how" lives in compiled check primitives (CTNs) and in the
channel that reaches the target. "Policy as data" is the first principle;
everything else follows from it.

A **CTN** is the unit of a single check. The engine spec expands it as
**Criterion Type Node**; Prooflayer's own docs sometimes say "Compliance Target
Node" — same thing, the compiled collector+executor+contract behind one check
type. Catalog: [writing-policies.md](writing-policies.md) (and the bundled CTN contract docs).

---

## 2. The pipeline: compile → execute → envelope

```
.esp file(s)
   │
   ▼  Compiler            untrusted text → validated AST
   │   (lexical → syntax → semantic → structural)
   ▼  Execution Engine    AST → ScanResult
   │   (resolution → collection → validation)
   ▼  Result Builder      ScanResult[] → one AssessorPackage
   ▼
signed AssessorPackage envelope
```

The engine does this in distinct stages, but you never touch them as a policy
author. What matters conceptually:

| Stage | In → out | Trust |
|---|---|---|
| **Compilation** | `.esp` → validated AST | untrusted → trusted. All parse/validation errors are caught **here**, before any scan. |
| **Resolution** | AST → execution context | trusted. References (`OBJECT_REF`/`STATE_REF`/`SET_REF`) are expanded — including a `SET_REF` to the bound-asset list (this is where [injection](injection-and-scoped-injection.md)'s resolved objects enter). |
| **Collection** | runs CTN collectors over the **channel** | trusted. One collection act = one observation. |
| **Validation** | collected data vs STATEs → outcome | trusted. Produces Pass/Fail/Error per [evaluation-and-outcomes.md](evaluation-and-outcomes.md). |
| **Result building** | results → `AssessorPackage` | controlled disclosure. One signed envelope. |

The **channel** (local / SSH / SSM / Bastion / WinRM) is *how* collection
reaches the target; the CTN is *what* it collects. Orthogonal — see
[assessor-cli.md](assessor-cli.md) and
[../components/channels.md](../components/channels.md).

---

## 3. Engine + data — why it scales

ESP is the **engine + data** pattern every scanner-at-scale uses: a small set of
compiled primitives + a large set of declarative policies.

| Tier | Form | Cardinality | Changes how |
|---|---|---|---|
| **CTN strategies** (primitives) | compiled check primitives, built into the engine | ~80 | engine release |
| **ESP policies** (data) | declarative `.esp` | target thousands | author + hot-load |

Tenable has ~100 NASL primitives and ~200k plugins; same shape. You extend
*coverage* by writing policies (data), not by recompiling the engine. Adding a
genuinely new *kind* of check (a new CTN) is the rarer, engine-developer event —
out of scope for policy authoring (see [writing-policies.md](writing-policies.md) §scope).

In Prooflayer the engine runs **in-process inside the server** (and is shared
with the `esp_assessor` CLI), so CLI and server produce byte-identical
envelopes — not a subprocess per scan. The system-level view is
[../components/evidence-and-ingest.md](../components/evidence-and-ingest.md).

---

## 4. The design principles (why a scan is a proof)

From the normative overview — these are the load-bearing commitments:

1. **Policy as data** — describe *what*, not *how*.
2. **Fail-fast validation** — errors caught at compile time, not mid-scan.
3. **Contract-driven extensibility** — CTN types are defined by contracts.
4. **Deterministic evaluation** — same policy + same state ⇒ same outcome.
5. **Compliance-ready output** — results map to standard formats (OSCAL).
6. **Trust boundaries** — inputs untrusted, outputs controlled.
7. **Verifiable results** — the **replay hash** binds outcome to compiled intent
   + contract, so an attestation is reproducible and comparable.
8. **Single envelope** — one signed `AssessorPackage` per scan, however many
   files; narrower views come from consumer-side filtering, not separate formats.

Principles 4 and 7 are the crux of Prooflayer's pitch: determinism makes the
[replay hash](../components/replay-hash.md) meaningful, and a stable hash is what
lets the same posture dedup across a fleet and prove "unchanged since last
scan." The envelope shape that carries all this is
[the-envelope.md](the-envelope.md).

---

## 5. Where to go next

- Read a policy's anatomy → [language-reference.md](language-reference.md)
- See how a verdict is computed → [evaluation-and-outcomes.md](evaluation-and-outcomes.md)
- Build one → [writing-policies.md](writing-policies.md)
- Understand one-policy-scans-N-assets → [injection-and-scoped-injection.md](injection-and-scoped-injection.md)
