# M365::Group

## Overview

An Entra ID group — security group, Microsoft 365 group (Unified), or
mail-enabled distribution group. Discovered via `m365_graph_query`
against `/groups`. Group membership is not pulled at discovery time;
it's lazily collected via Graph during policy evaluation when needed.

**Source:** Microsoft Graph `GET /v1.0/groups`
**Required Graph permission:** `Group.Read.All` (application)

---

## Asset shape

| Field                          | Source (Graph)          | Notes                                                                                       |
| ------------------------------ | ----------------------- | ------------------------------------------------------------------------------------------- |
| `asset_type`                   | constant                | `M365::Group`                                                                               |
| `provider_id`                  | `id`                    | Graph object id (UUID).                                                                     |
| `display_name`                 | `displayName`           | Falls back to `mail`, then `id`.                                                            |
| `metadata.description`         | `description`           |                                                                                             |
| `metadata.mail`                | `mail`                  | Primary SMTP for mail-enabled groups; null otherwise.                                       |
| `metadata.mail_enabled`        | `mailEnabled`           | Boolean.                                                                                    |
| `metadata.security_enabled`    | `securityEnabled`       | Boolean.                                                                                    |
| `metadata.group_types`         | `groupTypes`            | Array. `["Unified"]` = M365 group; `[]` = pure security group.                              |
| `metadata.visibility`          | `visibility`            | `Public`, `Private`, `Hiddenmembership`.                                                    |
| `metadata.created_at`          | `createdDateTime`       |                                                                                             |

---

## Common policy uses

- **Public M365 groups** holding sensitive content: `groupTypes` contains `"Unified"` AND `visibility = "Public"`
- **Security groups missing description**: `securityEnabled = true` AND `description` empty
- **Stale groups**: combine with audit log to detect zero-activity groups

---

## Related CTN

[`m365_graph_query`](m365_graph_query.md) — the underlying collector.
