# Replay-Hash Canonical Output Specification

**Status:** reference contract for independent verification.
**Audience:** anyone implementing a verifier — including a third party who does
not trust the producer.

The concept-level overview is [replay-hash.md](replay-hash.md); this page is the
**byte-exact contract**: the canonical pre-image the engine hashes, and the
procedure to recompute it.

---

## 1. What this is

The **canonical output** is the canonical manifest — the exact pre-image hashed
to produce a policy's `replay_hash`. A verifier recomputes `replay_hash` from the
manifest and confirms it matches. The manifest is the **only** thing that needs
to be exposed for hash verification.

Three deliberate properties:

- **No evidence, no findings, no actual observed values.** The outcome layer
  carries pass/fail booleans only. So the manifest can be published for
  verification without leaking the scanned system's data.
- **Not persisted.** The manifest is **reconstructed on demand**, keyed by
  `replay_hash` (or envelope id — see §9): resolve the attestation's policy +
  asset and re-run the pipeline up to the moment *before* execution (compile →
  scoped-inject the asset → resolve), which yields the intent + contract layers
  deterministically, then **inject the stored outcome** (per-field `passed`) and
  build the manifest. Same bytes, same hash, nothing stored.
- **Versioned.** `replay_hash_version` selects the rollup (1 or 2). The format
  is a frozen contract once published — see §8.

### What it proves (and does not)

- ✅ **Binding (trustless):** the manifest recomputes to `replay_hash` → this
  exact verdict came from this exact, readable check. Pure math; no trust in the
  producer.
- ➕ **Provenance (trust-rooted):** the signature over `replay_hash` says *who*;
  the transparency log says *when*. These rest on the producer's PKI and log, not
  on the recompute.
- ❌ **Truth of the observation:** the manifest excludes actual values, so it
  does **not** prove the verdict reflects the live system. That rests on the
  scanner that collected — inherent to agentless attestation.

Call it a **verifiable attestation of a verdict**, not evidence verification.

---

## 2. The hash primitive `H(x)`

Every hash in the manifest — criterion, per-object, block, policy — is produced
by the same primitive:

```
H(x) = "sha256:" + lowercasehex( SHA256( canonical_json(x) ) )
```

`canonical_json(x)`:

1. Serialize `x` to a JSON value.
2. **Recursively sort every object's keys** ascending by key string (Unicode-
   scalar / byte order). **Array element order is preserved** (not sorted).
3. Serialize **compact** — no insignificant whitespace.
4. Hash the UTF-8 bytes with SHA-256; lowercase-hex encode; prefix `sha256:`.

Notes for reimplementers:
- Struct field order in the inputs is irrelevant — step 2 re-sorts keys.
- The `sha256:` prefix is part of the string. Child hashes are embedded as these
  prefixed strings into the parent's input, then that parent input is itself
  `canonical_json`-ed and hashed.
- Number/string encoding follows a default JSON value model (sorted-key canonical
  JSON, not full RFC-8785 number normalization — see §8).

---

## 3. The canonical manifest schema (the canonical output)

```
ReplayManifest
├─ schema_version       : string
├─ replay_hash_version  : u8        # 1 (v1 rollup) | 2 (v2 per-object rollup)
├─ policy_id            : string
├─ platform             : string
├─ criticality          : string
├─ control_mappings     : [string]  # sorted; "FRAMEWORK:CONTROL_ID"
├─ criteria             : { <ctn_node_id> : CriterionReplay }   # keyed PER CTN
└─ tree_structure       : ReplayTreeNode                         # CRI rollup shape

CriterionReplay
├─ intent   : ReplayIntent      # from the resolved AST  (deterministic)
├─ contract : ReplayContract    # from the CTN contract  (deterministic)
└─ outcome  : ReplayOutcome     # the only execution-dependent layer

ReplayIntent
├─ ctn_type   : string
├─ test_spec  : { existence_check: string, item_check: string, state_operator: string|null }
├─ states     : { <state_name> : {
│        fields        : { <field_name> : { data_type, operation, expected_value, entity_check|null } },
│        record_checks : [ ReplayRecordCheckIntent ]
│   } }
└─ objects    : { <object_id> : { fields: { <name> : <json value> } } }

ReplayRecordCheckIntent
├─ data_type : string|null
└─ content   : Direct  { operation, expected_value }
             | Nested  { fields: { <dot.path> : { data_type, operation, expected_value, entity_check|null } } }

ReplayContract
├─ ctn_type            : string
├─ collector_id        : string
├─ collection_mode     : string          # "metadata" | "content" | "command" | ...
└─ validation_mappings : { <state_field> : <data_field> }   # sorted

ReplayOutcome                              # *** NO actual values ***
├─ status         : string                 # "Pass" | "Fail" | "Error"  (derived rollup)
└─ object_results : { <object_id> : {
        passed        : bool,              # per-OBJECT  (derived rollup)
        field_results : { <field_name> : { operation, expected, passed } }
   } }

ReplayTreeNode
= Leaf  { ctn_node_id : string }
| Block { logical_op : "AND"|"OR", negate : bool, children : [ReplayTreeNode] }
```

---

## 4. Outcome capture granularity

The manifest is **organized per-CTN** (`criteria` keyed by `ctn_node_id`), but
the outcome data goes deeper:

```
per CTN  →  per OBJECT (object_results)  →  per FIELD (field_results) → { operation, expected, passed }
```

The **only execution-dependent value is per-field `passed`.** `operation` and
`expected` also appear in the intent and are deterministic. The per-OBJECT
`passed` and the per-CTN `status` are **derived rollups** of the field booleans.

**Therefore: capture the outcome per CTN → per OBJECT → per FIELD.** A single
CTN-level pass/fail is too coarse — both to recompute the hash and to render a
readable verdict (e.g. a CIS rule with three record-field checks, each with its
own pass/fail).

For **v2**, the per-(CTN,OBJECT) leaf hashes already commit to the outcome and
are persisted as the per-object leaf; the policy hash can be re-rolled from those
+ reconstructed intent without re-deriving per-field. The readable manifest still
needs per-field for the outcome layer.

---

## 5. v1 rollup (`replay_hash_version = 1`)

Bundles all OBJECTs of a criterion into one criterion hash.

1. **Per-criterion hash**, for each `(ctn_node_id, CriterionReplay)`:
   `crit_hash[ctn_node_id] = H(CriterionReplay)`   *(intent + contract + outcome together)*
2. **Tree rollup** over `tree_structure`:
   - `Leaf{ctn_node_id}` → `crit_hash[ctn_node_id]` (or `"sha256:missing-criterion"` if absent)
   - `Block{logical_op, negate, children}` →
     `H({ logical_op, negate, child_hashes: sort([rollup(child) for child in children]) })`
     *(children sorted — AND/OR are commutative)*
3. **Policy hash**:
   `replay_hash = H({ schema_version, policy_id, platform, criticality, control_mappings, tree_hash })`

## 6. v2 rollup (`replay_hash_version = 2`)

Per-CTN-per-OBJECT leaves, so a single differing OBJECT diverges and identical
OBJECTs (same template across hosts) collapse.

1. **Per-object leaf hash**, for each criterion, for each `object_id` present in
   `outcome.object_results`:
   ```
   H(PerObjectReplay {
       intent:   { ctn_type, test_spec, states, object: intent.objects[object_id] },  # object_id KEY stripped — only fields enter
       contract: <ReplayContract>,
       outcome:  { passed: object_results[object_id].passed,
                   field_results: object_results[object_id].field_results }
   })
   ```
   OBJECTs declared but never collected (no outcome) are omitted.
2. Collect all leaf hashes across all criteria into a flat list; **sort**.
3. **Policy hash**:
   ```
   replay_hash = H({ schema_version, policy_id, platform, criticality,
                     control_mappings,
                     cri_tree_structure: tree_structure,   # preserves AND/OR/negate shape
                     ctn_object_hashes:  <sorted leaf hashes> })
   ```

The CRI tree structure is folded into the policy input so re-shaping the AND/OR
tree changes the hash even if the leaves are unchanged.

---

## 7. Verification procedure (third party)

Given a `replay_hash` and the canonical manifest (served on demand, §1):

1. Parse the manifest; read `replay_hash_version`.
2. Recompute per §5 (v1) or §6 (v2) using the `H` primitive of §2.
3. Compare to the claimed `replay_hash`. Equal ⇒ **the verdict and the readable
   check are exactly what this hash commits to** (trustless).
4. *(Provenance, optional, trust-rooted):* verify the producer's signature over
   `replay_hash` against the scanner-identity cert; check the hash's inclusion in
   the transparency log. These add *who/when*; they are not part of the recompute
   and rest on the producer's PKI/log.

A conforming verifier MUST report the trust boundary, not a single "VERIFIED":
- binding recomputed — no trust required;
- signature/log — trust the issuing PKI / the operator's log (until externally witnessed);
- observation truth — not attested.

---

## 8. Stability & versioning

This format is a **published contract**. Once a verifier exists in the wild:

- Do not change the `H` primitive, the canonicalization, the schema, or either
  rollup without bumping `replay_hash_version`. A silent change breaks every
  third-party verifier and shifts every historical hash.
- `replay_hash_version` is carried in the manifest and in the envelope; verifiers
  route on it.
- Open question before public release: pin the canonical JSON to a named standard
  (e.g. RFC-8785 JCS) so number/string encoding is language-independent. The
  current form is "sorted-key compact JSON," which two builds of the same
  implementation agree on but a Python/Go reimplementation must match exactly.

---

## 9. On-demand reconstruction

The manifest is regenerated per request, not stored. **Query by `replay_hash`
(or envelope / scan-result id) — not by `(asset, policy)`.** The hash identifies
a *specific* attestation; `(asset, policy)` is ambiguous (which scan?) and would
re-derive against the asset's *current* state. Keying on the hash anchors the
reconstruction to the exact stored result.

Lookup + rebuild:

1. **Resolve the query key.** `replay_hash` → the anchored attestation: the
   recorded scan that carries the bound asset, the policy (with the policy
   content fingerprint captured at scan time), and the per-(ctn,object) outcome.
2. **Rebuild intent + contract** by resolving that policy against that asset,
   **stopping before execution**: compile the policy → scoped-inject the
   asset values into the OBJECT(s) → resolve. This yields `intent` + `contract`
   byte-identical to the real run.
3. **Inject the stored outcome** (per-field `passed`, §4) from *that result*.
4. Build the canonical manifest and serve it.

Nothing about the manifest is persisted; intent + contract are derived per call,
and only the outcome is sourced from the recorded result.

### Fidelity boundary (for historical attestations)

Keying by the hash means "verify *this* attestation," which requires the inputs
*as they were at scan time*:

- **Outcome** — anchored to the stored result for that hash. ✅ always exact.
- **Intent (policy)** — rebuilt from the policy. Exact only if the policy is
  unchanged since the scan. For an edited policy, exact recompute needs the
  **policy content as-of the fingerprint recorded on the scan run**; this
  requires retaining policy content by that fingerprint, or the rebuilt intent
  diverges.
- **Intent (injected OBJECT fields)** — filled from asset metadata (`path`,
  `resource_id`, …). Exact only if the asset hasn't drifted on those identifier
  fields since the scan.

Consequence: **recent** attestations (policy + asset unchanged) recompute
exactly. **Historical** ones, after a policy edit or asset rename, may not — and
a verifier MUST report that distinctly as **"could not reproduce inputs,"** not
as **"hash failed to verify."** Conflating drift with a verification failure
would read as a broken proof when it is not.

---

See [transparency-and-verifiable-evidence.md](transparency-and-verifiable-evidence.md)
for how this hash is signed, logged, and exposed for verification, and
[replay-hash.md](replay-hash.md) for the plain-language overview.
