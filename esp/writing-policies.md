# Writing Policies

The practical workflow: from "I need to check X for control Y" to a compiled,
runnable `.esp`. Assumes you know the [language](language-reference.md) and
[how outcomes work](evaluation-and-outcomes.md).

> Want to do this **in the product** rather than on disk? The system-ui **ESP
> Policies** page is a git-backed editor — create/edit in the browser with
> history & one-click rollback. See [policy-editor.md](policy-editor.md).

---

## 1. The loop

```
pick the CTN ──▶ write the OBJECT ──▶ write the STATE ──▶ assemble the CRI ──▶ META + mapping ──▶ validate/run
 (what check)     (what to look at)    (what's expected)   (combine checks)    (identity)         (compile + scan)
```

### Step 1 — pick the CTN (the check type)

Find the CTN that performs your kind of check. The authoritative reference is
the bundled **[CTN contract docs](contracts/README.md)** — one Markdown doc per
CTN, organized by platform (Linux, AWS, Azure, Kubernetes, M365, …). Browse the
platform folder or `grep -ril "<keyword>" contracts/`. There are ~80 CTNs (200+
docs including the `_scoped` variants). The catalog with categories is
[language-reference.md](language-reference.md) and the system view is
[../components/evidence-and-ingest.md](../components/evidence-and-ingest.md).

> You **consume** CTNs; you don't write them. Authoring a new CTN (a compiled
> collector+executor+contract) is engine-developer work — see §5.

### Step 2 — write the OBJECT from the CTN's Object Fields

Each contract doc has an **Object Fields** table: field · type · required ·
example. Write your OBJECT using exactly those fields (no type keyword, no
operator — see [language-reference.md](language-reference.md) §2):

```esp
OBJECT bucket
    bucket_name `prooflayer-demo-findings`   # required, per the aws_s3_bucket contract doc
    region `us-east-1`                        # optional
OBJECT_END
```

### Step 3 — write the STATE from the sample responses

The same contract doc shows the **commands run** and **sample responses** — the
shape of the data your STATE compares against. Write typed STATE fields (or a
`record` check for nested/JSON data) asserting the compliant value:

```esp
STATE encrypted_and_versioned
    record
        field ServerSideEncryption.SSEAlgorithm string = `aws:kms`
        field Versioning.Status                 string = `Enabled`
    record_end
STATE_END
```

### Step 4 — assemble the CRI/CTN tree

Bind the TEST + STATE + OBJECT in a CTN, inside a CRI:

```esp
CRI AND
    CTN aws_s3_bucket
        TEST all all AND
        STATE_REF encrypted_and_versioned
        OBJECT_REF bucket
    CTN_END
CRI_END
```

Pick the TEST operands deliberately (existence/item/combinator — see
[evaluation-and-outcomes.md](evaluation-and-outcomes.md)): `TEST all all` for
"must exist and pass," `TEST none all` for an absence check, etc.

### Step 5 — META + control mapping

Add the seven required META fields and the mapping discipline
(`control_mapping ⊇ control_objective ⟺ impl_*`, IDs from the bundled catalogs).
Full rules: [meta-and-control-mapping.md](meta-and-control-mapping.md).

### Step 6 — validate and run

Compile + run locally to surface errors and confirm the verdict before linking
it to assets:

```bash
esp_assessor --channel local -o /tmp/out.json path/to/policy.esp
```

A clean compile and an expected Pass/Fail (not `Error`) means it's sound. Common
mistakes and what the error codes mean: [errors-and-gotchas.md](errors-and-gotchas.md).

To **test outside the container** (locally / in CI), build the open-source ESP
engine + CLI from <https://github.com/CurtisDSlone/Endpoint-State-Policy> and run the
same `esp_assessor` command there. See [assessor-cli.md](assessor-cli.md).

---

## 2. Make it scope-flexible (recommended)

If the check applies to many resources of one type, write it as a
**bind-and-inject** policy instead of hardcoding one OBJECT per resource: use
the CTN's `_scoped` variant + a placeholder SET, add the `target_asset_type`
META hint, and bind it to an asset — Prooflayer fans it out at dispatch. This is
the default style for cloud policies. Full mechanics:
[injection-and-scoped-injection.md](injection-and-scoped-injection.md).

---

## 3. A complete minimal example

A one-CTN policy that asserts only `root` holds UID 0 (a minimal
`linux_account_audit` test policy):

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

---

## 4. Authoring at scale — the policy-generation pipeline

Policies aren't usually hand-written one at a time; they come out of an upstream
**policy-generation pipeline** that ingests security benchmarks and emits `.esp`
files, AI-assisted then human-reviewed:

```
extract ─▶ controls DB ─▶ policy-gen ─▶ .esp ─▶ policy library
benchmark   normalized     generate +     (review)   versioned
(STIG/CIS/   controls +     stage                     set
 MITRE)      crosswalks
```

That pipeline carries its own authoring aids — a language quick-reference, a full
language guide, a starter policy template, the control statements that fill
`impl_` narratives, a keyword index, and per-platform batch generators. It is a
separate project; it connects to Prooflayer only through the compiled policy AST
and the `AssessorPackage` shape. The finished, versioned policy library and the
minimal one-CTN test policies are what ship for you to read and run.

---

## 5. Scope boundary — policies, not contracts

This guide covers **writing policies** (consuming existing CTNs). It does **not**
cover **authoring CTN contracts** — building new check types, which is
engine-developer work (a compiled collector + executor + contract, plus its
contract doc). For *what* a CTN is conceptually, see [how-esp-works.md](how-esp-works.md).
As a policy author, if no CTN fits your check, that's a request to the engine
team — not something you solve in `.esp`.
