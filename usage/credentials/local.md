# `local`

Singleton sentinel credential bound to the Prooflayer host itself. Carries
no secret material — the `local` channel runs `esp_assessor` in-process
against the VM where Prooflayer is deployed.

## What it represents

The Prooflayer scanner host as a scannable target. Whenever Prooflayer
needs to assess its own configuration (the VM the server is running on),
it uses the `local` channel + this credential. There's exactly one
instance of this credential per Prooflayer install, seeded automatically
by local discovery (the first `POST /api/inventory/discover/local` call).

**Operators should not create `local` credentials manually.** The
credential-create UI omits this kind from the dropdown. The
singleton is seeded on the first `POST /api/inventory/discover/local`
call.

## Payload fields

None. This kind has no fields — there's no secret to store. The
credential exists purely so the inventory model has a valid credential
to associate with `Local::Host` asset scans.

## Metadata fields

None used today. Metadata is left empty for this kind.

## How to provision

`POST /api/inventory/discover/local` (UI: Discover page → "Register
this host"). The endpoint:

1. Reads `/etc/os-release` and hostname facts from the local machine
2. Creates or updates the `Local::Host` asset record
3. Ensures a single `local` credential exists, creating it on first
   call

Idempotent: subsequent calls refresh OS facts but don't duplicate
the credential.

## How to add in Prooflayer

Not added manually. See "How to provision" above — calling the local
discovery endpoint creates it as a side effect.

If someone tries to create one via the API directly, the credential-create
endpoint accepts it (the `local` kind isn't specially blocked at the API
layer), but the UI doesn't surface it as an option, and the `Local::Host`
asset binding only ever references the auto-seeded singleton.

## Used by

- **In-process scans of the Prooflayer VM** — `Local::Host` asset
  scans dispatched via the `local` channel. The channel runs the
  `esp_assessor` binary as a subprocess of prooflayer-2 itself, with
  full filesystem + process access to the host
- **Self-attestation scans** — when a policy requires evidence about
  the scanner's own posture (e.g. "Prooflayer's host has FIPS mode
  enabled"), the `Local::Host` asset is the scan target and this
  credential is the binding

## Rotation

Not applicable. No secret to rotate; no expiry.

## Failure modes

| Symptom                                       | Likely cause                                                       |
|---                                            |---                                                                 |
| `credential 'local' not found`                 | Local discovery never run. Hit `POST /api/inventory/discover/local` |
| Multiple `local` credentials exist             | Manual API insertion bypassed the singleton idempotency — clean up by deleting duplicates |
| Local::Host asset has wrong credential_id      | Asset binding pre-dates the singleton seed; re-run local discovery to refresh the binding   |

## Security notes

- No secret material → nothing to leak.
- The `local` channel has full access to the Prooflayer host's filesystem
  + process tree by design. Anything `esp_assessor` can read on disk
  is in scope for a `Local::Host` scan.
- Compromise of the Prooflayer process itself is the broader security
  boundary; the `local` credential doesn't expand the blast radius
  beyond what process privileges already grant.
