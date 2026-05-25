# `github_pat`

Fine-grained GitHub Personal Access Token (or classic PAT) for
SDLC-layer discovery. Read-only across the org and repo APIs the
discoverer walks.

## What it represents

A token bound to a specific GitHub user that grants programmatic
access to repositories, orgs, and adjacent SDLC surface (workflows,
deploy keys, webhooks, branch protection). Prooflayer authenticates
as that user when calling the GitHub REST API.

For GitHub Enterprise Server (GHES) deployments, the same token kind
is used — `base_url` switches the API root.

## Payload fields

| Field      | Required | Description                                                                   |
|---         |---       |---                                                                            |
| `base_url` | yes      | API root. `https://api.github.com` for GitHub.com; `https://<host>/api/v3` for GHES |
| `token`    | yes      | Fine-grained PAT (`github_pat_*`) or classic PAT (`ghp_*`)                    |

## Metadata fields (non-secret, operator-set)

| Key            | Purpose                                                                        |
|---             |---                                                                             |
| `login`        | GitHub login the PAT belongs to (auto-populated by the Test Connection step)   |
| `account_type` | `User` or `Organization` (auto-populated)                                       |
| `expires_at`   | Date the PAT expires (operator types this from the GitHub UI; UI surfaces a warning N days before) |
| `scopes`       | Free-form note on the permission matrix granted                                |

## How to provision

GitHub.com → **Settings** → **Developer settings** →
**Personal access tokens** → **Fine-grained tokens**.

Recommended scope matrix for Phase 1 SDLC discovery:

| Scope target          | Permissions          | Why                                                  |
|---                    |---                   |---                                                   |
| Repository — Metadata | Read-only            | Repo identity, visibility, default branch             |
| Repository — Contents | Read-only            | Branch listing for protection rules                   |
| Repository — Administration | Read-only       | Branch protection, deploy keys                       |
| Repository — Webhooks | Read-only            | Webhook enumeration                                   |
| Repository — Actions  | Read-only            | Workflow file listing                                 |
| Organization — Members | Read-only           | Org membership for `SDLC::User → SDLC::Organization` |
| Organization — Administration | Read-only      | Org-level settings (SAML, IP allowlist, etc.)         |

Bind the PAT to **all repositories** for org-wide discovery, or to a
specific subset if scope-narrowing is required.

For GHES, mint the PAT in the same way on the GHES web UI; the
fine-grained scopes are equivalent.

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (`scanset-org-pat`, `customer-ghes`, …)
2. **Kind**: GitHub fine-grained PAT
3. **API base URL**: `https://api.github.com` (default) or your GHES API root
4. **Fine-grained PAT**: paste the `github_pat_...` value
5. **Metadata**: optional `login` / `account_type` / `expires_at` / `scopes`
6. Save → run the **Test connection** button on the cred to verify

## Used by

- **GitHub discovery** — enumerates orgs and repos accessible to the
  PAT, emitting `SDLC::Organization`, `SDLC::Repository`, `SDLC::User`,
  `SDLC::Pipeline`, `SDLC::Webhook`, and `SDLC::DeployKey` assets.
- All `github_*` CTNs read the token + API base URL from the scan
  environment, which Prooflayer populates from this credential.

## Rotation

Fine-grained PATs **always have an expiry** — GitHub forces a date
at mint time (default 90 days; max 1 year). Set `metadata.expires_at`
to the mint-time expiry so the UI can surface a warning chip 14 days
before.

Rotation flow:

1. Mint a new PAT with the same scope matrix
2. Use the **Rotate** action on the Prooflayer credential card
3. Paste the new token, save
4. Run **Test connection** to verify
5. Revoke the old PAT from the GitHub UI

Classic PATs (`ghp_*`) can be set to no-expiry; this is **strongly
discouraged**. Use fine-grained PATs and accept the 90-day rotation
cadence.

## Failure modes

| Symptom                                  | Likely cause                                                       |
|---                                       |---                                                                 |
| `401 Unauthorized` on Test connection    | Token expired, revoked, or pasted with extra whitespace            |
| `403 Forbidden` on a specific endpoint   | Scope matrix missing the permission required for that resource     |
| `404 Not Found` on org calls             | PAT not bound to the org (fine-grained PATs require explicit binding) |
| GHES connection failures                 | `base_url` doesn't end in `/api/v3`, or GHES is behind a proxy not reachable from the Prooflayer VM |

## Security notes

- Token is held as role-scoped plaintext at rest (no app-layer encryption).
- Prooflayer reads only — every CTN that uses this cred runs against
  read-only GitHub endpoints. There's no path from a Prooflayer
  discovery sweep to a GitHub write.
- Set per-org PATs rather than a single org-wide PAT when the customer
  has multiple GitHub orgs — smaller blast radius if any one cred
  leaks.
- Always set `metadata.expires_at` so the UI's expiry warning kicks
  in. Without it, the only sign of expiry is a discovery sweep failing.
