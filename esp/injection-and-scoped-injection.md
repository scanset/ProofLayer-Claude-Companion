# Injection & Scoped Injection

How Prooflayer makes **one policy file scan N resources without the author ever
naming them** — and how every policy can be **automatically attached to an asset
and scanned**. This is Prooflayer's layer *above* the ESP engine: the engine
only ever sees concrete, fully-resolved policies; injection is what produces
them at dispatch.

> Concept reference. This page explains the *idea*; the dispatch logic lives in
> the server, above the engine.

---

## 1. The problem

An ESP `DEF` block lists concrete `OBJECT`s — the things to check. The naive
model hard-codes them: one OBJECT per NSG, per storage account, per bucket. That
means editing policy text every time inventory changes, and a separate file per
scope (one NSG vs. all NSGs in a resource group). It doesn't scale, and it
couples policy content to your asset list.

**Injection moves object selection out of the policy text and into the
binding** — the link between a policy and an asset.

> **One line:** the *binding* determines the scope, not the policy text. The
> same `.esp` scans one resource or a thousand depending only on where it's
> linked.

---

## 2. The language hook: placeholder OBJECT + SET_REF

ESP itself provides the hook. Instead of concrete OBJECTs, the author writes a
**placeholder** inside a `SET`, carrying three directives:

```esp
SET targets union
    OBJECT t
        target `Microsoft.Network/networkSecurityGroups`   # the asset type to resolve
        link `contains`                                     # relation to walk from the bound asset
        behavior inject_from_bound_asset                    # marks this as the placeholder
    OBJECT_END
SET_END
```

The CTN then references that set with **`SET_REF`** — which (since ESP v2.1) is a
first-class CTN content operand: a CTN can take a whole SET, *including the
policy's bound-asset list*, as one block. During the engine's **resolution**
phase a `SET_REF` expands to its underlying objects — and that is exactly where
Prooflayer slots the resolved per-asset objects in. (Language detail:
[language-reference.md](language-reference.md) §5.)

---

## 3. Injection — walk → fill → splice

At **dispatch time**, *before* the engine compiles the file, Prooflayer resolves
the placeholder:

1. **Find** the placeholder OBJECT (the one with `behavior inject_from_bound_asset`); read its `target` (asset type) and `link` (relation).
2. **Walk** the asset graph from the bound asset to `target`-typed descendants, following `link` — a recursive walk over each asset's `parents`/`children` edges. The `link` directive picks which **relations** the walk follows; the default (`child`/`children`/`descendant`) walks only `contains` + `member_of`. Other structural relations (`references`, `attached_to`, `alias_of`, `installs`, `peers_with`) are opt-in by naming them in `link`; see the full [relation taxonomy](../components/inventory.md#the-asset-graph--link-taxonomy). A bound asset that *is* the target type matches at depth 0 (N=1).
3. **Fill** one concrete OBJECT per resolved asset, from that asset's metadata.
4. **Splice** the rendered OBJECTs into the SET, strip the directive fields, and hand the engine a fully concrete policy.

```
subscription ──contains──▶ resource group ──contains──▶ NSG ×N
   (bind here → fan out)                                   (or bind here → N=1)
```

So binding the same policy to a **subscription** fans out to every matching
resource under it; binding to a **resource group** scopes to that RG; binding to
a **single resource** scans just that one — all from one file, no edits.

---

## 4. Scoped injection — how each OBJECT's fields get filled

Injection needs to know *how to populate each OBJECT* from a resolved asset.
That's the **scoped contract** — a `<base>_scoped` CTN variant (e.g.
`az_nsg_scoped`) that:

- **Reuses the base CTN's collector + executor verbatim** — the scoped variant
  is the same check, re-presented under the `_scoped` name. No new check logic.
- **Carries a projection** that maps each OBJECT field to a **field source** —
  the rule for where the field's value comes from:

  | Field source | Fills the field from… |
  |---|---|
  | display name | the resolved asset's display name |
  | self metadata | the asset's own metadata (e.g. `resource_group`, `subscription_id`) |
  | literal | a constant in the projection |
  | linked | one hop to a neighbor asset (by relation/direction/neighbor type), then *its* metadata |

The asset's id is carried straight from the walk (no provider id is
reconstructed). A required field that can't resolve causes the dispatcher to
**skip that target and log it** — never emit a half-formed OBJECT.

The engine then receives an ordinary SET of N concrete OBJECTs and produces a
**per-resource verdict and replay-hash leaf for each** — not one rolled-up
pass/fail. That per-asset granularity is what makes per-resource drift and
evidence meaningful (see [../components/replay-hash.md](../components/replay-hash.md)).

---

## 5. Auto-attach — every policy, scanned, with minimal clicks

Injection makes a policy *scope-flexible*; **auto-linking** makes attaching it
*automatic*. Two pieces cooperate:

- **`target_asset_type`** — the optional META hint declaring which asset type a
  policy expects (see [meta-and-control-mapping.md](meta-and-control-mapping.md)).
  It's a hint + guardrail, asserted against the CTN's registered type at
  registration so a copy-paste typo is caught.
- **Auto-link** — `POST /api/inventory/asset-policies/auto-link` reconciles
  registered policies to discovered assets **by `target_asset_type`**, creating
  the bindings with no per-policy clicking.

The result is the intended end state: **discover assets → auto-link policies →
every policy is attached to the assets it applies to → scans fan out per
resource.** New resources discovered later are covered on the next reconcile/scan
with no policy edits. (M365 has a per-asset variant that live-re-queries a single
resource by id; same model, different fetch shape.)

---

## 6. End to end

```
.esp (placeholder + SET_REF) ──┐
                               │  Prooflayer dispatcher (above the engine)
bound asset(s) ────────────────┼─▶ walk asset graph → resolve N targets
  (via auto-link or manual)    │   → scoped projection fills each OBJECT (field sources)
                               │   → splice into the SET → fully-concrete policy
                               └─▶ engine: resolve SET_REF → collect → validate
                                   → N per-resource verdicts + N replay-hash leaves
                                   → one AssessorPackage → evidence + transparency log
```

**Worked example** — `az_nsg_scoped` bound to a subscription: the walk finds 3
NSGs; the projection fills `name ← display_name`,
`resource_group ← metadata.resource_group`,
`subscription ← metadata.subscription_id`; the engine tests `inj_0_<nsg-a>`,
`inj_1_<nsg-b>`, `inj_2_<nsg-c>` each against the policy's STATE, producing three
independent verdicts.

---

## 7. Why it matters

- **One file, any scope** — author once, bind anywhere; no per-resource files.
- **Inventory-driven** — new resources are covered automatically next scan; zero policy edits.
- **Per-resource evidence** — fan-out preserves an individual verdict + replay hash per asset.
- **Engine stays simple** — all of this is above the engine, which only ever compiles concrete, fully-resolved policies.

---

## 8. Authoring a scopeable check (for completeness)

Making a CTN scopeable is two small declarations on the *contract* side (engine-
developer work, not policy authoring): register the `_scoped` variant (it reuses
the base collector/executor) and declare its projection (the `target_asset_type`
+ a field source per OBJECT field). After that, **any** policy can use
`CTN <name>_scoped` with the placeholder SET. As a policy author you just *use*
the scoped variant — see [writing-policies.md](writing-policies.md) §2.
