# META & Control Mapping

The `META` block declares a policy's identity and how it maps to compliance
controls. Two layers: the **engine's normative META rules** (required fields,
formats, identity tuple) and **Prooflayer's control-mapping conventions** (the
`control_mapping` / `control_objective` / `impl_` discipline).

> Combines the normative ESP META requirements (full spec: [spec/07](spec/07_ESP_Meta_Requirements_v1_0_0.md)) with Prooflayer's control-mapping conventions.

---

## 1. Required fields (engine, normative)

Seven fields MUST be present (rule N-16). All META values are backtick strings.

| Field | Purpose | Format / rule |
|---|---|---|
| `esp_id` | Unique policy id across the corpus | lowercase-hyphen; rec. `{source}-{control-id}-{description}` |
| `version` | Policy **content** revision | SemVer (bump when content changes) |
| `dsl_schema_version` | ESP **language** version it conforms to | valid SemVer; compiler checks compatibility |
| `platform` | Target platform | lowercase: `linux`, `windows`, `azure`, `aws`, `kubernetes`, … |
| `criticality` | Severity | one of `critical` `high` `medium` `low` `info` (case-insensitive) |
| `control_mapping` | Framework→control mapping | `FRAMEWORK:CONTROL[,FRAMEWORK:CONTROL…]` (≥1 pair) |
| `title` | Human-readable title | concise; appears in reports/findings |

Missing or malformed required fields are **compile-time** validation errors
(`MissingRequiredField`, `InvalidCriticality`, `InvalidDslVersion`,
`InvalidControlMapping`).

**Policy identity tuple** (N-13): `(esp_id, version, dsl_schema_version)` — the
canonical id, serialized `esp_id:version:dsl_schema_version`. It's what caches
compiled policies and correlates results across scans. The **filename is not
load-bearing** — tooling reads `esp_id`.

### Recommended (engine)
`description`, `author`, `agent_type`, `tags`, `control_framework`, `control`.

---

## 2. Prooflayer extensions

On top of the engine fields, Prooflayer policies carry:

| Field | Purpose |
|---|---|
| `control_objective` | The bare control ID(s) this policy actually demonstrates (subset of `control_mapping`) |
| `impl_<FRAMEWORK>_<CONTROL>` | One narrative per objective explaining *how* the policy satisfies it |
| `target_asset_type` | Optional **binding hint** — which asset type this policy expects to be linked to/under. Drives the link picker + a registration guardrail; **not** a category. See [injection-and-scoped-injection.md](injection-and-scoped-injection.md). |

> Do **not** put the asset list or filenames in META. The targets are resolved
> at dispatch from the binding + graph (injection), not authored.

---

## 3. The control-mapping discipline

The rule that the repo's linters and reviews enforce:

```
control_mapping  ⊇  control_objective  ⟺  impl_*
  (broad crosswalk)   (bare IDs demonstrated)   (one narrative each — a bijection)
```

- **`control_mapping`** is the broad crosswalk — every framework/control this
  policy touches, comma-separated `FRAMEWORK:CONTROL`.
- **`control_objective`** is the subset actually *demonstrated* (bare IDs).
- **`impl_*`** — exactly **one** narrative per objective. Objectives and `impl_`
  keys are in bijection: every objective has an `impl_`, every `impl_` maps to an
  objective.

```esp
control_mapping  `KSI:CNA-IBP,NIST-800-53:SC-7`
control_objective `CNA-IBP`
impl_KSI_CNA_IBP `Isolation boundary protection is validated by ...`
```

### Formatting rules (enforced)

- **`impl_` keys use underscores**: `impl_CM_5_6`, **not** `impl_CM-5(6)`.
- **Don't prefix the framework in the impl key**: `impl_AU_12`, not `impl_NIST_AU_12`.
- **KSI form drops the `KSI-` prefix after the namespace**: write
  `KSI:IAM-APM` (not `KSI:KSI-IAM-APM`); objective `IAM-JIT`; narrative
  `impl_IAM_JIT`. A repo linter auto-normalizes this.

---

## 4. Control IDs come from the bundled catalogs — never invented

Authoritative control IDs live in the **bundled control catalogs**: NIST 800-53 rev5 + 800-171
rev2 (OSCAL), FedRAMP 20x FRMR **KSI**, and the baselines — validated against the
benchmark-extract crosswalk. **Never recall or invent a control ID**; look it up.

For `impl_` narratives, the control *statements* (e.g. the 60 KSI statements)
come from the bundled control statements maintained in the authoring pipeline's
controls catalog.

> Framework note: **KSI = FedRAMP 20x Key Security Indicators.** CMMC maps onto
> NIST 800-171. CIS and DISA-STIG appear in crosswalks but the mapping
> source-of-truth is the bundled catalogs.

---

## 5. Complete META example

```esp
META
    esp_id `ksi-cna-ibp-r9-selinux-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `linux`
    criticality `critical`
    control_mapping `KSI:CNA-IBP,NIST-800-53:SC-7,DISA-STIG:SV-258078`
    title `Rocky 9 SELinux must be enforcing`
    description `Validates SELinux is Enforcing at runtime and in config.`
    author `prooflayer`
    tags `rocky9,stig,selinux,fedramp`
    control_objective `CNA-IBP`
    target_asset_type `linux_host`
    impl_KSI_CNA_IBP `Isolation boundary protection is validated by confirming SELinux is Enforcing at runtime (/sys/fs/selinux/enforce = 1) and persisted in /etc/selinux/config, so enforcement survives reboot.`
META_END
```

The system-wide view of control mapping and how evidence rolls up into an SSP is
[../components/ssp-and-control-mapping.md](../components/ssp-and-control-mapping.md).
