# M365::User

## Overview

An Entra ID user identity. Discovered via `m365_graph_query` against
`/users`. One row per user, including guests (B2B) and service principals
that surface as users.

**Source:** Microsoft Graph `GET /v1.0/users`
**Required Graph permission:** `User.Read.All` (application)

---

## Asset shape

| Field                                | Source (Graph)                  | Notes                                                                                     |
| ------------------------------------ | ------------------------------- | ----------------------------------------------------------------------------------------- |
| `asset_type`                         | constant                        | `M365::User`                                                                              |
| `provider_id`                        | `id`                            | Graph object id (UUID, immutable).                                                        |
| `display_name`                       | `displayName`                   | Falls back to `userPrincipalName`, then `mail`, then `id` if blank.                       |
| `metadata.user_principal_name`       | `userPrincipalName`             | Login name (UPN).                                                                         |
| `metadata.mail`                      | `mail`                          | Primary SMTP address; may differ from UPN.                                                |
| `metadata.user_type`                 | `userType`                      | `Member` or `Guest` (B2B externally federated user).                                      |
| `metadata.account_enabled`           | `accountEnabled`                | Boolean. Disabled users still surface — gate on this in policies.                         |
| `metadata.created_at`                | `createdDateTime`               | Date the user record was created in Entra.                                                |
| `metadata.sign_in_activity`          | `signInActivity`                | Nested object with `lastSignInDateTime`, `lastNonInteractiveSignInDateTime`, etc.         |

---

## Common policy uses

- **Stale accounts**: `signInActivity.lastSignInDateTime` older than N days
- **Unused accounts**: `accountEnabled = false`
- **Guest sprawl**: `userType = 'Guest'` count
- **Service accounts misclassified**: `userType = 'Member'` with no `signInActivity`

---

## Related CTN

[`m365_graph_query`](m365_graph_query.md) — the underlying collector.
