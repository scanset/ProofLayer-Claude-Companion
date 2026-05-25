# github_deploy_key

## Overview

Fetches `GET /repos/{owner}/{repo}/keys/{key_id}` and surfaces deploy-key
hygiene fields: read-only flag, verification status, creation date,
last-used timestamp, and a computed "days since last use" for staleness
checks. One CTN call per `SDLC::DeployKey` asset.

**Platform:** GitHub
**Collection Method:** Single authenticated HTTPS GET per object.
**Target asset_type:** `SDLC::DeployKey`

---

## Object Fields

| Field    | Type    | Required | Description                  | Example                  |
| -------- | ------- | -------- | ---------------------------- | ------------------------ |
| `owner`  | string  | **Yes**  | Owner login.                 | `scanset`                |
| `repo`   | string  | **Yes**  | Repo name.                   | `Endpoint-State-Policy`  |
| `key_id` | integer | **Yes**  | Numeric deploy-key id.       | `99`                     |

---

## Commands Executed

```
GET https://api.github.com/repos/{owner}/{repo}/keys/{key_id}
Headers:
  Authorization: Bearer <GITHUB_TOKEN>
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

**Requires PAT scope:** `Repository: Deploy keys: Read`.

**Sample response (abbreviated):**

```json
{
  "id": 99,
  "key": "ssh-rsa AAAA...",
  "title": "deploy-key-prod",
  "verified": true,
  "created_at": "2025-01-12T08:14:22Z",
  "read_only": true,
  "added_by": "octocat",
  "last_used": "2026-04-15T17:22:08Z"
}
```

**Notes:**
- `last_used` is `null` when GitHub has never observed the key in use,
  or when the PAT lacks scope to see it.
- `key` carries the public half of the SSH key. The CTN does not
  re-emit it (already captured by discovery on the asset row's
  `metadata.key`).

---

## Collected Data Fields

| Field                  | Type    | Always Present | Source                                                              |
| ---------------------- | ------- | -------------- | ------------------------------------------------------------------- |
| `found`                | boolean | Yes            | `true` on HTTP 200                                                  |
| `read_only`            | boolean | When found     | `read_only` — `false` means the key can push, usually wrong for a deploy key |
| `verified`             | boolean | When found     | `verified`                                                          |
| `title`                | string  | When found     | `title`                                                             |
| `created_at`           | string  | When found     | `created_at` (ISO 8601)                                             |
| `last_used_at`         | string  | When found     | `last_used` or `""` if absent                                       |
| `days_since_last_use`  | integer | When found     | days between now and `last_used_at`, or `-1` if never used / unparseable |
| `ever_used`            | boolean | When found     | `true` iff `last_used_at` is non-empty                              |

---

## State Fields

| State Field            | Type    | Allowed Operations                |
| ---------------------- | ------- | --------------------------------- |
| `found`                | boolean | `=`, `!=`                         |
| `read_only`            | boolean | `=`, `!=`                         |
| `verified`             | boolean | `=`, `!=`                         |
| `title`                | string  | `=`, `!=`                         |
| `created_at`           | string  | `=`, `!=`                         |
| `last_used_at`         | string  | `=`, `!=`                         |
| `days_since_last_use`  | int     | `=`, `!=`, `<`, `<=`, `>`, `>=`   |
| `ever_used`            | boolean | `=`, `!=`                         |

---

## Failure Modes

Standard:
- 200 → fields populated.
- 401 → `CollectionError`.
- 403 → `found=false`, PAT lacks `Deploy keys: Read`.
- 404 → `found=false`, key was deleted between discovery + scan.
- 5xx / 429 → retry-with-backoff.

---

## Collection Strategy

| Property                 | Value                                            |
| ------------------------ | ------------------------------------------------ |
| Collector ID             | `github_deploy_key_collector`                    |
| Collector Type           | `github_deploy_key`                              |
| Collection Mode          | Metadata                                         |
| Required Capabilities    | `github_pat_env`, `github_deploy_keys_read`      |
| Required Env Vars        | `GITHUB_TOKEN`, `GITHUB_BASE_URL` (optional)     |
| Expected Collection Time | ~300ms                                           |

---

## Control Mapping (sample)

| Field check                                       | Control(s)                                |
| ------------------------------------------------- | ----------------------------------------- |
| `read_only = false`                               | least privilege — NIST AC-6, CMMC AC.L2-3.1.5 |
| `days_since_last_use > 90` (typical threshold)    | CMMC IA.L2-3.5.7 / IA.L2-3.5.10, NIST IA-5(1), IA-5(13) (credential hygiene, stale credential identification) |
| `ever_used = false` AND `days_since_last_use < 0` | informational — unused since creation; consider deletion |
