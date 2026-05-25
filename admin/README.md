# Administration — Tasks Inside Prooflayer

What an administrator does *within* the running product: log in and manage
sessions, issue the tokens and keys other identities authenticate with, govern
scanning credentials, and run the policy registry and scheduling. This is the
**application** layer.

> For host/container lifecycle (processes, PKI files, backup) see
> [ops/](../ops/README.md). For the conceptual "what is this part" reference see
> [components/](../components/README.md). Most write actions below require a
> logged-in operator session with admin capability.

---

## 1. Users & access (system-ui auth)

The alpha uses a **single super-admin** model (routes under
`/system-ui/auth/`). There is no operational-user creation, no password-change
flow, and no bootstrap-finalize ceremony — the seeded super-admin credentials
just work. A one-time **EULA** modal gates the sign-in screen on first visit
(acceptance is stored per-version in the browser; bumping the EULA version
re-prompts).

| Task | How |
|---|---|
| Log in | `super-admin` / `prooflayer` (single super-admin, seeded on first boot) |
| See who you are | `GET /system-ui/auth/me` |
| End a session / all sessions | `DELETE /system-ui/auth/session` / `…/sessions/{id}` |

Passwords are hashed with PBKDF2 through OpenSSL (no pure-Rust crypto anywhere
in the server).

> **Account recovery** (if the default credentials were changed at the host
> level) is a host-level operation against the system credentials store. See
> [ops/ §account recovery](../ops/README.md#7-account-recovery).

---

## 2. Keys & webhooks (`/api/admin/*`)

The alpha's admin routes issue the non-session identities and outbound
integrations the rest of the system uses:

### Persistent API keys
Long-lived API keys scoped to a purpose. The one that matters in the alpha is
the **CMR viewer** key — it's how the headless `/cmr-api/*` oversight surface
authenticates. Issue a CMR key here and hand it to whoever consumes the
oversight view (an AO, a SIEM/SOAR, or an AI assistant acting for the user).

### Webhooks
Configure outbound webhook endpoints; the server delivers on events such as
scan completion. Admin-gated.

---

## 3. Credential governance (`/api/inventory/credentials`)

Scanning credentials are the keys to everything the scanner can reach — manage
them deliberately.

| Task | Endpoint |
|---|---|
| Add a credential | `POST /api/inventory/credentials` |
| List / inspect (non-secret metadata only) | `GET …/credentials`, `GET …/{id}` |
| Rotate the secret | `PUT …/credentials/{id}/rotate` |
| Delete | `DELETE …/credentials/{id}` |

The 12 kinds — `aws_access_key`, `aws_role`, `azure_spn`, `azure_spn_cert`,
`m365_delegated_refresh`, `gcp_sa_key`, `ssh_key`, `winrm_password`,
`github_pat`, `kube_config`, `local`, `network_target` — each with payload
fields, required privileges, how-to-obtain, and rotation cadence in
**[usage/credentials/](../usage/credentials/README.md)**. Credential secrets are
secured by host disk encryption plus scoped, least-privilege internal access
isolation (read-on-dispatch only), not app-layer crypto — a deliberate
architecture decision.

> Admin hygiene: give each scanning credential the **least privilege** its
> discovery/scan scope needs (a read-only SPN, a read-only IAM policy). The
> fixture READMEs in [test_fixtures/credentials/](../test_fixtures/credentials/README.md)
> describe minimal-privilege credentials to create for evaluation.

---

## 4. Policy registry & scheduling

The administrator decides **what gets checked, where, and how often**.

| Task | Endpoint |
|---|---|
| Register `.esp` files into the registry | `POST /api/inventory/policies/bulk-register` |
| List / retire a policy | `GET /api/inventory/policies`, `…/{id}/retire` |
| Link a policy to an asset (bind) | `POST /api/inventory/asset-policies` |
| Auto-link by `target_asset_type` | `POST /api/inventory/asset-policies/auto-link` |
| Pause / resume / archive a link | `PATCH …/asset-policies/{asset}/{policy}/status` |
| Set a per-link schedule (cron) | `PUT …/asset-policies/{asset}/{policy}/schedule` |
| Trigger a scan now | `POST /api/inventory/assets/{id}/scan-now`, `…/scan-now/batch` |

A policy is **bound to an asset**; at dispatch the server injects the concrete
targets (see [esp/injection-and-scoped-injection.md](../esp/injection-and-scoped-injection.md)).
Registration records the optional `target_asset_type` hint and warns on
mismatch — that hint, plus scoped injection at dispatch, is the whole
"what-applies-to-what" mechanism.

> Writing or changing the `.esp` files themselves (not just registering them) is
> done on the **ESP Policies** page — a git-backed editor with history and
> rollback. See [esp/policy-editor.md](../esp/policy-editor.md).

---

## 5. Frameworks & control mapping

The control catalog (FedRAMP 20x KSI, NIST 800-53, NIST 800-171) is seeded at
first boot from the bundled catalogs. Each policy's control metadata
auto-attaches its signed evidence to the framework controls at query time — no
manual linking — and the rolled-up per-control view is readable through the CMR
controls surface (`/cmr-api/controls`). Authoritative control IDs come from the
bundled catalogs, never from memory — see
[components/ssp-and-control-mapping.md](../components/ssp-and-control-mapping.md).

> **Not in the alpha:** SSP *prose* authoring, the 3PAO assessment workflow
> (SAP/SAR, control plans, findings/dispute), and POA&M administration are GRC
> *authoring/workflow* concerns. Prooflayer is the evidence engine; those are a
> partner surface (e.g. an OSCAL feed into a dedicated GRC product) and are not
> present in the alpha.

---

## Admin checklist for a fresh evaluation

1. Accept the EULA on the sign-in screen and log in as `super-admin` / `prooflayer`.
2. Add a least-privilege scanning credential (or skip — use the local channel).
3. Register the policy tree (`bulk-register`) if not auto-loaded.
4. Issue a **CMR viewer key** if you want to exercise the AO surface.
5. Link a policy to an asset (or `auto-link`), optionally set a schedule.
6. Run a scan and confirm evidence + a transparency entry appear.
