# ESP — Endpoint State Policy

Everything about ESP: what it is, how the engine works, how to write policies,
and how Prooflayer's **injection** layer makes one policy scan every matching
asset automatically. This folder is the canonical ESP reference for the guide.

> ESP is the declarative DSL Prooflayer scans with — *policy as data*. You
> describe what should be true; the engine collects actual state through a
> channel and emits a signed, replay-hashable evidence envelope. ESP is a
> normative language spec (engine v2.0.0); policies are produced by an upstream
> authoring pipeline; per-CTN detail is in the bundled CTN contract docs.

---

## Read in this order

| # | Page | What it covers |
|---|---|---|
| 1 | [how-esp-works.md](how-esp-works.md) | What ESP is, the compile→execute→envelope pipeline, the engine+data pattern, the design principles that make a scan a *proof*. Start here. |
| 2 | [language-reference.md](language-reference.md) | The DSL: META + DEF; OBJECT / STATE / CRI / CTN; SET & SET_REF; TEST; types, operators, scoping. With a full annotated example. |
| 3 | [evaluation-and-outcomes.md](evaluation-and-outcomes.md) | How TEST/CRI/STATE evaluate → Pass/Fail/Error; existence/item/combinator; Fail-vs-Error; determinism; the replay-hash tie-in. |
| 4 | [meta-and-control-mapping.md](meta-and-control-mapping.md) | Required META fields + identity tuple; the `control_mapping ⊇ objective ⟺ impl_` discipline; catalogs as source of truth. |
| 5 | [the-envelope.md](the-envelope.md) | The `AssessorPackage` wire shape: polymorphic host, observations, policy results, filtering tiers, replay-hash invariants, OSCAL mapping. |
| 6 | [writing-policies.md](writing-policies.md) | The authoring loop: pick a CTN from the contract docs, write OBJECT/STATE, assemble the CRI, map controls, validate/run; the policy-generation pipeline. |
| 7 | [injection-and-scoped-injection.md](injection-and-scoped-injection.md) | **How one policy auto-attaches to assets and scans each one** — placeholder OBJECT, SET_REF, walk→fill→splice, scoped contracts, auto-link. |
| 8 | [assessor-cli.md](assessor-cli.md) | Running `esp_assessor`: channels, flags, examples, exit codes. |
| 9 | [errors-and-gotchas.md](errors-and-gotchas.md) | The error model (codes like E043) and the authoring traps that bite (ASCII-only, OBJECT vs STATE, `behavior`, typed fields). |
| 10 | [policy-editor.md](policy-editor.md) | The in-product **ESP Policies** page: create/edit/delete in the browser, git-backed **history & rollback** (every change is a commit), and how it relates to the registry. |

### Bundled reference (browsable)

The full authoritative source material is bundled in the guide so you can
traverse it directly:

| Folder | What |
|---|---|
| [contracts/](contracts/README.md) | **The CTN contract docs** — one Markdown doc per CTN (object fields, commands, sample responses), by platform. ~200 docs. The reference you read to write an OBJECT/STATE. |
| [spec/](spec/README.md) | **The normative ESP language specification** — the 12 numbered spec documents (grammar, types, evaluation, META, error model, canonical schema, trust model) + signing. Consult for edge cases. |

### Open source — the engine you test with

ESP is an **open-source engine**. To compile and run policies (i.e. to *test*
what you write — see [assessor-cli.md](assessor-cli.md)), use the engine
directly:

- **ESP engine** — the compiler + execution engine + scanner CLI:
  <https://github.com/CurtisDSlone/Endpoint-State-Policy>
- **Agent-SDK** — the public repo for **developing CTN contracts and testing
  ESP** policies against the engine: <https://github.com/CurtisDSlone/Agent-SDK>

Prooflayer embeds this engine; the `spec/` and `contracts/` above are bundled
copies of its language spec and check contracts. For local policy testing
outside the container, build the engine from the repo above.

---

## The one-minute model

```
.esp policy ─▶ Compiler (→ AST) ─▶ Execution Engine (collect over a channel,
                                    validate vs STATE) ─▶ signed AssessorPackage
```

- A policy is **META** (identity + control mapping) + **DEF** (OBJECTs = what to
  look at, STATEs = what's expected, CRI/CTN = the evaluation tree).
- A **CTN** (Criterion Type Node — Prooflayer also says "Compliance Target
  Node") is one compiled check; ~80 exist, each documented per-platform in the
  bundled CTN contract docs. You *use* CTNs; authoring new ones is engine work.
- Evaluation is **deterministic** → the **replay hash** over
  `(intent, contract, outcome)` is stable, which is what makes a scan a
  comparable, reproducible *proof*.
- **Injection** lets you bind one policy to an asset and have Prooflayer fan it
  out to every matching resource at dispatch — one file, any scope, per-resource
  evidence.

---

## Quick example

A complete one-CTN policy (asserts only `root` holds UID 0):

```esp
META
    esp_id `test-linux-account-audit-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `linux`
    criticality `info`
    control_mapping `CIS:7.2.2`
    title `linux_account_audit uid_zero (only root)`
META_END

DEF
    OBJECT uid0
        check `uid_zero`
    OBJECT_END
    STATE observed
        found boolean = true
        compliant boolean = true
    STATE_END
    CRI AND
        CTN linux_account_audit
            TEST all all AND
            STATE_REF observed
            OBJECT_REF uid0
        CTN_END
    CRI_END
DEF_END
```

Run it: `esp_assessor --channel local -o /tmp/out.json policy.esp`.

---

## Related (system-level, in components/)

ESP concepts that also matter system-wide live in [../components/](../components/README.md):
[replay-hash](../components/replay-hash.md) (the hash in depth),
[evidence-and-ingest](../components/evidence-and-ingest.md) (how Prooflayer
ingests/signs/stores the envelope), [channels](../components/channels.md) (the
transports), and [posture-and-drift](../components/posture-and-drift.md). For the
in-product scan workflow see [../usage/](../usage/README.md).
