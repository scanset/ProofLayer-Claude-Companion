# Errors & Authoring Gotchas

How ESP reports problems, and the handful of mistakes that bite policy authors
most. Most errors are caught at **compile time** (so you find them before a
scan); a few only surface at **runtime** as `Outcome::Error`.

> Reflects the normative ESP error model — full spec: [spec/08](spec/08_ESP_Error_Model_v1_0_0.md).

---

## 1. The three error categories

| Category | When | Effect |
|---|---|---|
| **ParseError** | tokenization / grammar fails | compilation fails — no policy |
| **ValidationError** | symbol / reference / type / structural / META checks fail | compilation fails — no policy |
| **EvaluationError** | runtime collection / execution fails | policy compiled, CTN → `Outcome::Error` |

Compile errors carry a code, a message, a **source span** (line:col), a
severity, and a recommended action:

```
E090 [Medium] Duplicate symbol 'config' in global scope
  --> policy.esp:15:5
   = first declared at policy.esp:8:5
   = help: Use unique identifiers within each scope
```

---

## 2. Codes you'll actually hit

| Code | Means | Usually because |
|---|---|---|
| **E043** GrammarViolation | EBNF violation | a type keyword on an OBJECT, uppercase `BEHAVIOR`, or other syntax slips (see gotchas) |
| E021 UnterminatedString | a backtick string isn't closed | missing closing `` ` `` (or a stray non-ASCII char swallowing the lexer) |
| E042 UnmatchedDelimiter | block start without end | a missing `*_END` (`OBJECT_END`, `STATE_END`, `CTN_END`, `CRI_END`, `DEF_END`) |
| E090 DuplicateSymbol | identifier reused in one scope | a global `STATE foo` and global `OBJECT foo` |
| E091 SymbolShadowing | local shadows global | a CTN-local `STATE x` when a global `STATE x` exists |
| E094 MultipleCtnObjects | >1 local OBJECT in a CTN | put extra objects at DEF level and `OBJECT_REF` them |
| E110 UndefinedReference | `*_REF` target not found | a typo'd `STATE_REF`/`OBJECT_REF`/`SET_REF` name |
| E180 TypeIncompatibility | operator not valid for the type | e.g. `contains` on an `int`, or `>` on a `boolean` |
| E200 SetConstraintViolation | SET operand count wrong | `intersection` needs 2+, `complement` exactly 2 |
| E230 InvalidBlockOrdering | blocks out of order | CTN content order is `TEST → STATE_REF → OBJECT_REF → SET_REF → local STATE → local OBJECT` |
| E242 EmptyCriteriaBlock | a `CRI` has no children | every CRI needs ≥1 CTN or nested CRI |
| E246/E247 META | META absent / a field invalid | missing required field, bad `criticality`, malformed `control_mapping` |

(Full ranges: lexical E020–E028, syntax E040–E050, symbols E051–E095,
references E110–E140, semantic E180–E200, structural E230–E247.)

---

## 3. Runtime errors → `Outcome::Error`

These compile fine but fail during the scan, producing `Error` (not `Fail`) for
that CTN — a *system* problem, not non-compliance:

- **Collection:** `AccessDenied` (permission), `CollectionTimeout`,
  `ObjectNotFound`, `MissingCollectionField`.
- **Registration:** `NoContractRegistered` / `NoCollectorRegistered` /
  `NoExecutorRegistered` — the CTN type isn't built into the engine (typo in the
  CTN name, or a contract that doesn't exist).

The Fail-vs-Error rule is in [evaluation-and-outcomes.md](evaluation-and-outcomes.md) §1.

---

## 4. Authoring gotchas (the ones that recur)

These produce confusing or runtime-only failures — internalize them:

1. **OBJECT has no type keyword.** `OBJECT foo TYPE sysctl_parameter` → **E043**.
   The CTN type goes on the `CTN` line; the OBJECT is just `field \`value\`` pairs.
2. **STATE needs a type keyword + operator.** `found = true` is wrong; write
   `found boolean = true`.
3. **`behavior` is lowercase.** `BEHAVIOR recurse true` → E043. Also it's
   `behavior recurse true`, not `BEHAVIOR recursive_scan max_depth N`.
4. **String literals must be ASCII.** An em-dash, smart-quote, or other
   non-ASCII char in a backtick string breaks the lexer — often with a
   *misleading* error pointing at a **later** line. Guard:
   `grep -P "[^\x00-\x7F]" policy.esp`.
5. **`impl_` keys use underscores, no framework prefix.** `impl_CM_5_6`, not
   `impl_CM-5(6)` or `impl_NIST_AU_12`. See [meta-and-control-mapping.md](meta-and-control-mapping.md).
6. **Typed OBJECT fields must match the engine's typed element.** Some fields
   (e.g. module/name/version/type/path on certain CTNs) resolve to a *typed*
   element, not a generic field — a mismatch fails at **runtime**, invisible to
   the compiler. Check the CTN's contract doc (object fields + sample responses).
7. **`int` ≠ `float`.** No implicit coercion (rule N-7) — operands must match
   the declared type.
8. **`file_content` doesn't glob paths.** Use `behavior recurse true` over a
   directory OBJECT instead of `*.conf` in `path`.

---

## 5. A non-ESP gotcha that looks like one: channel-config drift

If a scan fails at **runtime** with `unknown variant <kind>` during
deserialization — that's not an ESP error. The channel configuration is a shared
contract between the server (which writes it when dispatching a scan) and the
scanner (which reads it to run); if a new channel kind was added but the server
and scanner versions don't match, the older peer rejects the variant. Fix: make
sure both are on matching versions. See
[../ops/README.md](../ops/README.md#5-troubleshooting).

---

## 6. Validate before you ship

Compile/run the policy locally with the CLI to surface compile errors and see
the outcome before linking it to assets:

```bash
esp_assessor --channel local -o /tmp/out.json path/to/policy.esp
```

A clean compile + an expected Pass/Fail (not Error) means the policy is sound.
See [assessor-cli.md](assessor-cli.md). To test outside the container, build the
open-source ESP engine from <https://github.com/CurtisDSlone/Endpoint-State-Policy>.
