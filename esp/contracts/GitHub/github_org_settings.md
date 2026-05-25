# github_org_settings

## Overview

Fetches `GET /orgs/{login}` against the GitHub REST API and surfaces the
org-level posture-relevant flags as typed STATE fields. This is the
authoritative source for the "what blast radius does an org-side
misconfiguration carry?" question — default repo permission, member
permissions, 2FA enforcement, etc.

**Platform:** GitHub (api.github.com or a GHES `/api/v3` host)
**Collection Method:** Single authenticated HTTPS GET per object via the
shared `_github_common` client (reqwest blocking + retry-with-backoff +
GitHub-flavored 404/403 handling).
**Target asset_type:** `SDLC::Organization`

---

## Object Fields

| Field   | Type   | Required | Description                                         | Example   |
| ------- | ------ | -------- | --------------------------------------------------- | --------- |
| `login` | string | **Yes**  | Organization login (slug). The asset_list iterator typically derives this from the asset's `metadata.login` (or `metadata.id` after stripping the `github-org:` prefix). | `scanset` |

---

## Commands Executed

```
GET https://api.github.com/orgs/{login}
Headers:
  Authorization: Bearer <GITHUB_TOKEN>
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

**Sample response (abbreviated):**

```json
{
  "login": "scanset",
  "id": 245420446,
  "two_factor_requirement_enabled": false,
  "web_commit_signoff_required": false,
  "default_repository_permission": "write",
  "members_can_create_repositories": true,
  "members_can_create_public_repositories": true,
  "members_can_create_private_repositories": true,
  "members_can_change_repo_visibility": true,
  "members_can_delete_repositories": true,
  "members_can_invite_outside_collaborators": true
}
```

---

## Collected Data Fields

| Field                                          | Type    | Always Present | Source                              |
| ---------------------------------------------- | ------- | -------------- | ----------------------------------- |
| `found`                                        | boolean | Yes            | `true` if HTTP 200 + body parsed    |
| `org_id`                                       | integer | When found     | `id`                                |
| `login`                                        | string  | When found     | `login`                             |
| `two_factor_requirement_enabled`               | boolean | When found     | `two_factor_requirement_enabled`    |
| `web_commit_signoff_required`                  | boolean | When found     | `web_commit_signoff_required`      |
| `default_repository_permission`                | string  | When found     | `default_repository_permission`     |
| `members_can_create_repositories`              | boolean | When found     | same                                |
| `members_can_create_public_repositories`       | boolean | When found     | same                                |
| `members_can_create_private_repositories`      | boolean | When found     | same                                |
| `members_can_change_repo_visibility`           | boolean | When found     | same                                |
| `members_can_delete_repositories`              | boolean | When found     | same                                |
| `members_can_invite_outside_collaborators`     | boolean | When found     | same                                |

---

## State Fields

| State Field                                | Type    | Allowed Operations                    | Maps To Collected Field |
| ------------------------------------------ | ------- | ------------------------------------- | ----------------------- |
| `found`                                    | boolean | `=`, `!=`                             | `found`                 |
| `org_id`                                   | int     | `=`, `!=`, `<`, `<=`, `>`, `>=`       | `org_id`                |
| `login`                                    | string  | `=`, `!=`                             | `login`                 |
| `two_factor_requirement_enabled`           | boolean | `=`, `!=`                             | same                    |
| `web_commit_signoff_required`              | boolean | `=`, `!=`                             | same                    |
| `default_repository_permission`            | string  | `=`, `!=`                             | same                    |
| `members_can_create_repositories`          | boolean | `=`, `!=`                             | same                    |
| `members_can_create_public_repositories`   | boolean | `=`, `!=`                             | same                    |
| `members_can_create_private_repositories`  | boolean | `=`, `!=`                             | same                    |
| `members_can_change_repo_visibility`       | boolean | `=`, `!=`                             | same                    |
| `members_can_delete_repositories`          | boolean | `=`, `!=`                             | same                    |
| `members_can_invite_outside_collaborators` | boolean | `=`, `!=`                             | same                    |

---

## Failure Modes

| HTTP status | CTN behavior                                                     |
| ----------- | ---------------------------------------------------------------- |
| 200         | `found=true`, all fields populated from response.                |
| 401         | `CollectionError`. Token rejected — operator re-mints the PAT.   |
| 403         | `found=false`, warning attached. PAT lacks scope on this org.    |
| 404         | `found=false`, warning attached. Org doesn't exist / unreachable. |
| 5xx / 429   | Retry up to 3 times with `Retry-After` honor (max 30s backoff). After exhaustion, `found=false`. |
| Network     | Same retry behavior, then `found=false` with warning.            |

---

## Collection Strategy

| Property                 | Value                                                        |
| ------------------------ | ------------------------------------------------------------ |
| Collector ID             | `github_org_settings_collector`                              |
| Collector Type           | `github_org_settings`                                        |
| Collection Mode          | Metadata                                                     |
| Required Capabilities    | `github_pat_env`                                             |
| Required Env Vars        | `GITHUB_TOKEN` (set by resolver from `GithubPat` credential). `GITHUB_BASE_URL` optional, defaults to `https://api.github.com`. |
| Expected Collection Time | ~400ms                                                       |

---

## Control Mapping (sample, not exhaustive)

Findings derived from this CTN map to:
- **2FA enforcement gap** → CMMC IA.L2-3.5.3, NIST IA-2(1), IA-2(2)
- **Members can delete repositories** → high blast radius; informational, no direct control
- **Default repository permission == "write" or "admin"** → least-privilege violations; map to NIST AC-6, CMMC AC.L2-3.1.5
