# Control Mapping (and where the SSP fits)

**Status: built (evidence auto-rolls-up to controls). SSP *prose authoring* is
out of scope for the alpha — see "Scope boundary" below.**

## Control mapping — evidence rolls up to a framework

Every ESP policy declares its control linkage in its metadata (see
[esp/meta-and-control-mapping.md](../esp/meta-and-control-mapping.md)):

```
control_mapping  `KSI:CNA-IBP,NIST-800-53:SC-7`   # broad crosswalk (the superset, ⊇)
control_objective `CNA-IBP`                        # the bare ID(s) actually demonstrated
impl_KSI_CNA_IBP `...narrative...`                 # one narrative per objective (bijection)
```

Rule: **`mapping ⊇ objective ⟺ impl_`**. Control IDs come from the seeded
**bundled control catalogs** (NIST 800-53 rev5 + 800-171 rev2, FedRAMP 20x FRMR
KSI, and baselines), validated against the benchmark crosswalk — never invented
or recalled. The KSI form drops the `KSI-` prefix after the namespace
(`KSI:IAM-APM`, objective `IAM-JIT`, `impl_IAM_JIT`). Frameworks the alpha ships
catalogs for: FedRAMP 20x KSI, NIST 800-53, NIST 800-171 (CMMC maps onto
800-171).

## The self-maintaining control story

The differentiating idea: a policy's control metadata **auto-attaches its signed
evidence to the framework controls at the moment you query a control** — no
human links evidence to a control by hand. As scans run, each control's
implementation stays backed by current, signed, replayable evidence
automatically. You can read this rolled-up view through the CMR controls surface
(`/cmr-api/controls`), which reports, per control, how many checks pass/fail and
links back to the underlying proofs.

The control *narrative* (the human prose that says "here's how we satisfy this
control") is authored upstream; the **evidence linkage** is what Prooflayer keeps
current automatically.

> Honest framing: the auto-attach is real and queryable; treat the narrative
> prose as something an external GRC product owns, not Prooflayer.

## Scope boundary

Prooflayer is the **verifiable evidence engine**. SSP *prose authoring* and
people/process GRC are a partner concern (e.g. an OSCAL feed into a dedicated GRC
product such as a FedRAMP authoring tool), not something Prooflayer tries to own
— and the SSP-authoring surface is **not present in the alpha**. Feature test:
*deepens the evidence engine* → in scope; *authors documents / manages process*
→ out. What ships is the evidence-backed control mapping above, not a document
editor.

Related: [evidence-and-ingest.md](evidence-and-ingest.md),
[replay-hash.md](replay-hash.md).
