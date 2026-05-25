# github_repo_metadata

## Overview

Fetches `GET /repos/{owner}/{repo}` against the GitHub REST API and
surfaces repo-level posture flags: visibility, archived/fork state,
default branch, web-commit-signoff requirement, and the
`security_and_analysis` block (secret scanning, push protection,
Dependabot security updates, and GHAS / CodeQL when available).

**Platform:** GitHub (api.github.com or a GHES `/api/v3` host)
**Collection Method:** Single authenticated HTTPS GET per object via
`_github_common`.
**Target asset_type:** `SDLC::Repository`

---

## Object Fields

| Field   | Type   | Required | Description           | Example                  |
| ------- | ------ | -------- | --------------------- | ------------------------ |
| `owner` | string | **Yes**  | Owner login (org or user). | `scanset`           |
| `repo`  | string | **Yes**  | Repo name (slug).     | `Endpoint-State-Policy`  |

---

## Commands Executed

```
GET https://api.github.com/repos/{owner}/{repo}
Headers:
  Authorization: Bearer <GITHUB_TOKEN>
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

**Sample response (abbreviated):**

```json
{
  "id": 1088032859,
  "name": "Endpoint-State-Policy",
  "full_name": "scanset/Endpoint-State-Policy",
  "private": false,
  "visibility": "public",
  "default_branch": "main",
  "archived": false,
  "disabled": false,
  "fork": false,
  "allow_forking": true,
  "web_commit_signoff_required": false,
  "security_and_analysis": {
    "secret_scanning": { "status": "disabled" },
    "secret_scanning_push_protection": { "status": "disabled" },
    "dependabot_security_updates": { "status": "disabled" }
  }
}
```

**Note:** `security_and_analysis.advanced_security` (CodeQL / GHAS) only
appears on paid plans. When absent, the CTN reports
`advanced_security_enabled = false`.

---

## Collected Data Fields

| Field                                       | Type    | Always Present | Source                                                    |
| ------------------------------------------- | ------- | -------------- | --------------------------------------------------------- |
| `found`                                     | boolean | Yes            | `true` on HTTP 200                                        |
| `private`                                   | boolean | When found     | `private`                                                 |
| `visibility`                                | string  | When found     | `visibility` ("public" \| "private" \| "internal")        |
| `archived`                                  | boolean | When found     | `archived`                                                |
| `disabled`                                  | boolean | When found     | `disabled`                                                |
| `fork`                                      | boolean | When found     | `fork`                                                    |
| `default_branch`                            | string  | When found     | `default_branch`                                          |
| `web_commit_signoff_required`               | boolean | When found     | `web_commit_signoff_required`                             |
| `allow_forking`                             | boolean | When found     | `allow_forking`                                           |
| `secret_scanning_enabled`                   | boolean | When found     | `security_and_analysis.secret_scanning.status == "enabled"` |
| `secret_scanning_push_protection_enabled`   | boolean | When found     | `security_and_analysis.secret_scanning_push_protection.status == "enabled"` |
| `dependabot_security_updates_enabled`       | boolean | When found     | `security_and_analysis.dependabot_security_updates.status == "enabled"` |
| `advanced_security_enabled`                 | boolean | When found     | `security_and_analysis.advanced_security.status == "enabled"`. False when block is absent (free-plan repos). |

---

## State Fields

| State Field                                 | Type    | Allowed Operations |
| ------------------------------------------- | ------- | ------------------ |
| `found`                                     | boolean | `=`, `!=`          |
| `private`                                   | boolean | `=`, `!=`          |
| `visibility`                                | string  | `=`, `!=`          |
| `archived`                                  | boolean | `=`, `!=`          |
| `disabled`                                  | boolean | `=`, `!=`          |
| `fork`                                      | boolean | `=`, `!=`          |
| `default_branch`                            | string  | `=`, `!=`          |
| `web_commit_signoff_required`               | boolean | `=`, `!=`          |
| `allow_forking`                             | boolean | `=`, `!=`          |
| `secret_scanning_enabled`                   | boolean | `=`, `!=`          |
| `secret_scanning_push_protection_enabled`   | boolean | `=`, `!=`          |
| `dependabot_security_updates_enabled`       | boolean | `=`, `!=`          |
| `advanced_security_enabled`                 | boolean | `=`, `!=`          |

---

## Failure Modes

Same as `github_org_settings`. 200 → populated. 401 → CollectionError.
403/404 → `found=false` with warning. 5xx/429 → retry-with-backoff,
then `found=false`.

---

## Collection Strategy

| Property                 | Value                              |
| ------------------------ | ---------------------------------- |
| Collector ID             | `github_repo_metadata_collector`   |
| Collector Type           | `github_repo_metadata`             |
| Collection Mode          | Metadata                           |
| Required Capabilities    | `github_pat_env`                   |
| Required Env Vars        | `GITHUB_TOKEN`, `GITHUB_BASE_URL` (optional) |
| Expected Collection Time | ~400ms                             |

---

## Control Mapping (sample)

- `secret_scanning_enabled = false` → CMMC IA.L2-3.5.10, NIST IA-5 (secret hygiene)
- `dependabot_security_updates_enabled = false` → CMMC RA.L2-3.11.2 (vulnerability monitoring), NIST RA-5
- `archived = false` AND last activity > N days → operational hygiene (not a primary control)
