# ESP Language Reference

The structure of an `.esp` policy: the blocks, what goes in each, the types and
operators, and the scoping rules. This is the *what you write* reference; for
*how it's evaluated* see [evaluation-and-outcomes.md](evaluation-and-outcomes.md),
and for the authoring workflow see [writing-policies.md](writing-policies.md).

> Summarizes the normative ESP grammar, lexical rules, type system, and symbol
> resolution (full spec: [spec/](spec/README.md)). Keywords are case-sensitive.

---

## 1. File shape

A policy is two blocks — optional `META`, then `DEF`:

```
esp_file ::= metadata? definition
```

In practice every Prooflayer policy has both. `META` declares identity and
control mapping (full rules in [meta-and-control-mapping.md](meta-and-control-mapping.md));
`DEF` declares what to check. Keywords are **case-sensitive**, files **MUST be
UTF-8**, and `#` starts a comment anywhere whitespace is allowed.

---

## 2. The `DEF` block

`DEF` holds zero or more **definition elements** followed by one or more
**criteria** (`CRI`) blocks:

```
DEF
    <elements: VAR / STATE / OBJECT / SET / RUN>
    <one or more CRI blocks>
DEF_END
```

| Element | What it is |
|---|---|
| `OBJECT` | **What to look at** — the target's address/selector (a file path, a resource id, a parameter name). |
| `STATE` | **What's expected** — typed field assertions the collected data must satisfy. |
| `CRI` / `CTN` | **The evaluation tree** — `CRI` combines criteria with `AND`/`OR`; each `CTN` is one check that binds a TEST + STATE + OBJECT. |
| `VAR` | A typed named value, referenceable with `VAR <name>`. |
| `RUN` | A runtime computation (string/arithmetic/collection ops) producing a value. |
| `SET` / `SET_REF` | A set of objects (union/intersection/complement); `SET_REF` references one — central to [injection](injection-and-scoped-injection.md). |

### OBJECT — no type keyword, no operator

An OBJECT is just `field \`value\`` pairs. The **CTN type goes on the `CTN`
line, never on the OBJECT.** OBJECTs declared at `DEF` level are global
(referenceable via `OBJECT_REF`); declared inside a `CTN` they're local.

```esp
OBJECT ssh_config
    path `/etc/ssh`
    filename `sshd_config`
    behavior recurse false
OBJECT_END
```

OBJECT elements include simple fields, `module_*` fields (PowerShell verb/noun),
`parameters`/`select` blocks, `behavior` specs, `FILTER` blocks, `SET_REF`, and
inline `SET`s.

### STATE — type keyword and operator REQUIRED

A STATE field is `field_name <type> <operator> <value>` (plus an optional
entity check). STATEs at `DEF` level are referenceable via `STATE_REF`; inside a
`CTN` they're local.

```esp
STATE secure_settings
    PermitRootLogin string = `no`
    PasswordAuthentication string = `no`
    MaxAuthTries int <= VAR auth_limit
STATE_END
```

For **structured data** (JSON, API responses), use a `record` check with nested
`field` paths (dotted, with `*` wildcards and `[index]`):

```esp
STATE collected
    record
        field settings.tls.minVersion string = `1.2`
        field rules.*.action string != `allow`
    record_end
STATE_END
```

### CRI / CTN — the evaluation tree

`CRI <AND|OR>` wraps criteria; criteria nest, and the leaves are `CTN` blocks. A
`CTN` names a check type and binds a TEST to a STATE and an OBJECT:

```esp
CRI AND
    CTN file_content
        TEST all all AND          # existence  item  state-combinator
        STATE_REF secure_settings
        OBJECT_REF ssh_config
    CTN_END
CRI_END
```

**CTN content MUST appear in this order** (normative rule N-6):
`TEST` → `STATE_REF*` → `OBJECT_REF*` → `SET_REF*` → local `STATE*` → local
`OBJECT?`. A CTN may carry a local STATE/OBJECT inline instead of referencing
global ones.

The `TEST` operands (full semantics in [evaluation-and-outcomes.md](evaluation-and-outcomes.md)):

| Operand | Values |
|---|---|
| existence check | `all` · `any` · `none` · `at_least_one` · `only_one` |
| item check | `all` · `at_least_one` · `only_one` · `none_satisfy` |
| state combinator (optional) | `AND` · `OR` · `ONE` |

`CRI` also takes an optional `negate_flag` (`true`) to invert the result.

---

## 3. Types and operators

Data types: `string`, `int`, `float`, `boolean`, `binary`, `record_data`,
`version`, `evr_string`. **`int` and `float` are not interchangeable — there is
no implicit coercion** (normative rule N-7).

| Operator group | Operators | Notes |
|---|---|---|
| comparison | `=` `!=` `>` `<` `>=` `<=` | strings compare lexicographically; `version`/`evr_string` compare semantically |
| string | `ieq` `ine` `contains` `starts` `ends` `not_contains` `not_starts` `not_ends` | string-only |
| pattern | `pattern_match` `matches` | regex, string-only |
| set | `subset_of` `superset_of` | requires collection from a SET |

String literals are **backtick-delimited** (`` `value` ``); also `r\`...\``
(raw), and triple-backtick multiline forms. Literals must be **ASCII** in
practice — see [errors-and-gotchas.md](errors-and-gotchas.md).

---

## 4. Scoping rules

| Scope | Declared at | Referenceable by | Visible outside? |
|---|---|---|---|
| **Global** | `DEF` level | `STATE_REF` / `OBJECT_REF` / `SET_REF` / `VAR` | yes |
| **Local** | inside a `CTN` | — | no |

- Identifiers MUST be unique within a scope **across all symbol types** — a
  global `STATE foo` and a global `OBJECT foo` collide (N-3).
- Local symbols MUST NOT **shadow** a global of the same name (N-5).
- Two different CTNs may each have a local `STATE bar` — different scopes, fine.

---

## 5. SET, SET_REF, FILTER (and why they matter for injection)

A `SET` composes objects with `union` (1+ operands), `intersection` (2+), or
`complement` (exactly 2); operands are `OBJECT_REF`s, inline `OBJECT`s,
`SET_REF`s, or filtered object refs. A `FILTER include|exclude` narrows a set by
`STATE_REF`.

```esp
SET config_files union
    OBJECT_REF ssh_config
    FILTER include
        STATE_REF secure_settings
    FILTER_END
SET_END
```

**`SET_REF` is a first-class CTN content operand (v2.1).** A CTN can reference a
whole SET — including the policy's **bound-asset list** — as one block. That is
the language hook Prooflayer's **injection** fills at dispatch: the author
writes a placeholder SET, and Prooflayer resolves it to the real per-asset
objects before the engine runs. See
[injection-and-scoped-injection.md](injection-and-scoped-injection.md).

---

## 6. VAR and RUN (computation)

`VAR <name> <type> <value>` declares a reusable value. `RUN <target> <op>`
computes one at runtime — ops include `CONCAT`, `SPLIT`, `SUBSTRING`,
`REGEX_CAPTURE`, `ARITHMETIC`, `COUNT`, `UNIQUE`, `MERGE`, `EXTRACT`. The result
is referenceable via `VAR <target>`.

```esp
VAR max_auth_tries int 4
RUN auth_limit ARITHMETIC
    VAR max_auth_tries
    - 1
RUN_END
# auth_limit now usable as `VAR auth_limit`
```

---

## 7. A complete example

A two-CTN SSH-hardening policy (from the normative grammar doc) — global STATE +
OBJECT, a SET with a filter, one referenced STATE and one local STATE:

```esp
META
    esp_id `policy-ssh-hardening-001`
    version `2.1.0`
    dsl_schema_version `1.0.0`
    platform `linux`
    criticality `high`
    control_mapping `NIST-800-53:AC-6,CIS:5.2.1`
    title `SSH Server Hardening Policy`
META_END

DEF
    VAR max_auth_tries int 4
    RUN auth_limit ARITHMETIC
        VAR max_auth_tries
        - 1
    RUN_END

    STATE secure_settings
        PermitRootLogin string = `no`
        PasswordAuthentication string = `no`
        MaxAuthTries int <= VAR auth_limit
    STATE_END

    OBJECT ssh_config
        path `/etc/ssh`
        filename `sshd_config`
        behavior recurse false
    OBJECT_END

    CRI AND
        CTN file_content
            TEST all all AND
            STATE_REF secure_settings
            OBJECT_REF ssh_config
        CTN_END

        CTN file_permissions
            TEST all all
            STATE permission_check          # local STATE
                mode int = 600
                owner string = `root`
            STATE_END
            OBJECT_REF ssh_config
        CTN_END
    CRI_END
DEF_END
```

---

## 8. Limits (recommended)

Symbols/definition 10,000 · string literal 1 MB · nesting depth 10 · identifier
255 chars · line 4,096 chars · file 10 MB · SET operands 100 · CTN per CRI
1,000.

Next: [evaluation-and-outcomes.md](evaluation-and-outcomes.md) (how this
evaluates to Pass/Fail/Error), then [writing-policies.md](writing-policies.md)
(turning a control into a policy).
