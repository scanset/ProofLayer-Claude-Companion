# Surfaces — Operator & Oversight Views

**Status: built (one operator SPA + a headless oversight API in the alpha).**

Two surfaces serve two stakeholders, both reading from the **same evidence
stream**. The data is one; the lens differs. (Operational walkthrough:
[usage/](../usage/README.md).)

| Surface | Stakeholder | Auth | What it's for |
|---|---|---|---|
| **system-ui** | operator / SOC / admin | login (session token) | The control plane: discovery, scheduling, scanning, posture, evidence, inventory, policy registry, user/session admin. |
| **CMR** — Continuous Monitoring Record | Authorizing Official (AO) / oversight | API key (CMR viewer) | Read-only oversight of the same evidence: posture, findings, controls, per-asset history, and on-demand proof verification. |

## Alpha specifics

- **system-ui** ships as a browser app, served over TLS in the container.
- **CMR is headless (API only)** in the alpha — a read-only HTTP surface
  authenticated with a CMR viewer key. There is no separate CMR UI bundle yet;
  a consumer (an AO, a SIEM/SOAR integrator, or an AI assistant given a key)
  drives it directly. Issue a CMR key from
  [admin/](../admin/README.md#2-keys--webhooks-apiadmin).
- CMR is the surface that exposes **independent proof verification** — given a
  scan's replay hash, it reconstructs and recomputes the verdict and serves the
  signer's public key + certificate chain. See
  [transparency-and-verifiable-evidence.md](transparency-and-verifiable-evidence.md).

> Vocabulary note: "CMR" (Continuous Monitoring Record) is the current name for
> the AO oversight surface; earlier drafts called it the AO view.

## Why one stream, many lenses

The whole point of the [proof contract](replay-hash.md) is that the *same*
signed, replayable, transparency-logged evidence satisfies the operator and the
AO simultaneously — nobody re-keys data into a separate system, and everyone can
independently verify the same chain. system-ui is the control plane that
produces the evidence; CMR is a pure read projection over it.

## Not in the alpha

GRC *authoring and workflow* surfaces are deliberately out of scope for the
alpha: there is no 3PAO assessment-workflow app, no SSP **prose** authoring, no
plan-of-action (POA&M) management, and no public trust-center page. Prooflayer's
job is the **verifiable evidence engine**; document authoring and people/process
GRC are a partner concern (e.g. an OSCAL feed into a dedicated GRC product). What
*does* carry forward is **control mapping** — evidence rolling up to framework
controls — see [ssp-and-control-mapping.md](ssp-and-control-mapping.md).
