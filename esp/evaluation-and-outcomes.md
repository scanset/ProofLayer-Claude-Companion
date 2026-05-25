# Evaluation & Outcomes

How a policy turns into a verdict: what `TEST` means, how `STATE`s and `CRI`
trees combine, and the difference between `Fail` and `Error`. Evaluation is
**deterministic** — same policy + same system state ⇒ same outcome, findings,
and evidence.

> Reflects the normative ESP evaluation semantics — full spec: [spec/06](spec/06_ESP_Evaluation_Semantics_v1_0_0.md).
> The language shapes are in [language-reference.md](language-reference.md).

---

## 1. The three outcomes

Every evaluation produces one of three:

| Outcome | Meaning |
|---|---|
| **Pass** | All required conditions met — compliant. |
| **Fail** | Evaluation completed, but a condition was not met. |
| **Error** | Evaluation could not complete (a *system* problem). |

The **Fail-vs-Error distinction** is the one people get wrong — it's about
*whether collection succeeded*, not about the verdict:

| Situation | Outcome |
|---|---|
| Field present but value doesn't match | **Fail** |
| Field/record path missing from collected data | **Fail** |
| Collector couldn't run (permission denied) | **Error** |
| Collector timed out / target unreachable | **Error** |

> Prooflayer adds a fourth *posture* state, **`unknown`** (the engine enum's
> default — e.g. never scanned), which is distinct from these evaluation
> outcomes and must be preserved end-to-end. See
> [../components/posture-and-drift.md](../components/posture-and-drift.md).

---

## 2. STATE evaluation

A STATE field compares collected data to the expected value with its operator,
yielding a boolean. **Multiple fields in one STATE combine with implicit AND** —
all must pass:

```esp
STATE secure_file
    permissions string = `0600`     # field 1  ┐
    owner       string = `root`     # field 2  ┘  STATE passes iff both pass
STATE_END
```

A field that's **missing** from the collected data → **Fail** (collection
succeeded, the field just isn't there). Collection failing entirely → **Error**.

When a CTN references **multiple STATEs**, they combine via the `state_operator`
(the optional third TEST operand, default `AND`):

| `state_operator` | Object passes when… |
|---|---|
| `AND` | all referenced STATEs pass |
| `OR` | any STATE passes |
| `ONE` | exactly one STATE passes |

---

## 3. TEST — `existence` then `item`

`TEST <existence_check> <item_check> [state_operator]`. The engine resolves the
candidate objects (after `OBJECT_REF`/`SET_REF` expansion and filtering), checks
**existence** against how many resolved, then checks **item** against how many
passed STATE validation.

**Existence check** (how many objects must exist):

| Check | Passes when |
|---|---|
| `all` | found == expected |
| `any` | always (no existence constraint) |
| `none` | found == 0 (absence check) |
| `at_least_one` | found ≥ 1 |
| `only_one` | found == 1 |

**Item check** (how many existing objects must pass STATE):

| Check | Passes when |
|---|---|
| `all` | every existing object passes |
| `at_least_one` | ≥ 1 passes |
| `only_one` | exactly 1 passes |
| `none_satisfy` | none pass (all fail) |

Common forms: `TEST all all` (all exist, all pass) · `TEST at_least_one all`
(≥1 exists, all that exist pass) · `TEST none all` (nothing should exist) ·
`TEST any at_least_one` (may not exist, but if any do, ≥1 passes).

Flow: **resolve objects → apply filters → existence_check → (if it passes)
item_check → CTN outcome.**

---

## 4. CRI logic — combining criteria

`CRI AND` / `CRI OR` combine child criteria (nested CRIs or CTNs). **There is no
short-circuiting** — every child is always evaluated, so all failures and all
evidence are recorded.

**`CRI AND`** → Pass iff all children Pass; else Error if any child Error;
otherwise Fail.

| Children | Result |
|---|---|
| [Pass, Pass, Pass] | Pass |
| [Pass, Fail, Pass] | Fail |
| [Pass, Error, Pass] | Error |

**`CRI OR`** → Pass-dominant: Pass if any child Passes; Error only if *all*
children Error; otherwise Fail.

| Children | Result |
|---|---|
| [Fail, Fail, Pass] | Pass |
| [Error, Error, Pass] | Pass |
| [Error, Fail, Fail] | Fail |
| [Error, Error, Error] | Error |

**Negate flag** (`CRI AND true`) inverts the block: Pass↔Fail, **Error stays
Error**.

CRIs **nest** for arbitrary logic — `(a OR b) AND c`:

```esp
CRI AND
    CRI OR
        CTN check_a ...
        CTN check_b ...
    CRI_END
    CTN check_c ...
CRI_END
```

---

## 5. Order, error recovery, determinism

- The tree is traversed **depth-first** in document order, but the logical
  result is **order-independent** (declaration/reference/child order don't
  change the verdict — operations are associative).
- An `Error` at one CTN does **not** stop its siblings: they're still evaluated
  and their findings recorded; the Error just propagates per CRI rules.
- Given the same policy and the same system state, the engine MUST produce the
  same outcome, findings, and evidence. That determinism is what makes the
  **replay hash** meaningful.

---

## 6. From outcome to replay hash

The verdict isn't just stored — it's bound into the **replay hash** over
`(intent, contract, outcome)`. v2 hashing (`replay_hash_version = 2`) computes
this per **(criterion, OBJECT)** pair rather than per criterion, giving a leaf
hash per resolved object — which is what makes per-resource drift meaningful
after [injection](injection-and-scoped-injection.md) fans a policy out. The full
treatment (identity-free hashing, the three-level hierarchy) is in
[../components/replay-hash.md](../components/replay-hash.md); how the outcome is
carried on the wire is in [the-envelope.md](the-envelope.md).
