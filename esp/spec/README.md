# ESP Language Specification (normative)

The normative ESP specification, bundled into the guide. The pages under
[../](../README.md) (how-esp-works, language-reference, evaluation-and-outcomes,
meta-and-control-mapping, the-envelope, errors-and-gotchas) are the **working
reference** distilled from these documents; this folder is the **authoritative
source** to consult for an edge case.

> Don't read these end-to-end — pull the one document the question needs.

> These are bundled copies of the **open-source** ESP engine's specification:
> <https://github.com/scanset/Endpoint-State-Policy>. To compile/run policies
> against the engine, build it from there (see [../assessor-cli.md](../assessor-cli.md)).

## Load which when

| Question / symptom | Document |
|---|---|
| Architecture overview, output model, design principles | [01_ESP_Overview_v1_0_0.md](01_ESP_Overview_v1_0_0.md) |
| Tokenization, keywords, string-literal rules | [02_ESP_Lexical_Rules_v1_0_0.md](02_ESP_Lexical_Rules_v1_0_0.md) |
| Parse error / grammar question (the EBNF) | [03_ESP_Grammar_EBNF_v2_1_0.md](03_ESP_Grammar_EBNF_v2_1_0.md) |
| Type mismatch / operation-not-allowed | [04_ESP_Type_System_v1_0_0.md](04_ESP_Type_System_v1_0_0.md) |
| Symbol already declared / scoping / shadowing | [05_ESP_Symbol_Resolution_v1_0_0.md](05_ESP_Symbol_Resolution_v1_0_0.md) |
| Wrong Pass/Fail/Error; TEST or CRI logic | [06_ESP_Evaluation_Semantics_v1_0_0.md](06_ESP_Evaluation_Semantics_v1_0_0.md) |
| Required META fields, field-format validation | [07_ESP_Meta_Requirements_v1_0_0.md](07_ESP_Meta_Requirements_v1_0_0.md) |
| Compiler error-code lookup (E0xx) | [08_ESP_Error_Model_v1_0_0.md](08_ESP_Error_Model_v1_0_0.md) |
| Output schema / envelope shape (v2 current) | [09_ESP_Canonical_Schema_v2_1_1.md](09_ESP_Canonical_Schema_v2_1_1.md) |
| Output schema (v1 legacy, for reference) | [09_ESP_Canonical_Schema_v1_1_0.md](09_ESP_Canonical_Schema_v1_1_0.md) |
| Trust boundaries, signing, filtering tiers | [10_ESP_Trust_Model_v1_2_0.md](10_ESP_Trust_Model_v1_2_0.md) |
| Runtime configuration knobs | [11_ESP_Configuration_v1_0_0.md](11_ESP_Configuration_v1_0_0.md) |
| Logging behavior | [12_ESP_Logging_v1_0_0.md](12_ESP_Logging_v1_0_0.md) |
| Policy / envelope signing procedures | [SIGNING.md](SIGNING.md) |

The DSL surface (grammar, types, evaluation) is the **v1.0.0** baseline; the
**output envelope** is **v2.x** (polymorphic host, top-level observations,
`replay_hash_version`) — see `09_ESP_Canonical_Schema_v2_1_1.md`. The alpha's
engine is pinned at v2.0.0.
