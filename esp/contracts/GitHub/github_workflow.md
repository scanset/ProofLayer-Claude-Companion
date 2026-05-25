# github_workflow

## Overview

Fetches `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}` and
surfaces the workflow's identity + state. The numeric `workflow_id` is
the stable OIDC SAN binding anchor used by the CI daemon enrollment
flow — it does not change when the workflow YAML file is renamed.

This CTN handles the **workflow record metadata**. SHA-pinning analysis
of the YAML's `uses:` declarations is a separate (future) sibling CTN
(`github_workflow_content`) — out of scope here.

**Platform:** GitHub
**Collection Method:** Single authenticated HTTPS GET per object.
**Target asset_type:** `SDLC::Pipeline`

---

## Object Fields

| Field         | Type    | Required | Description                                       | Example     |
| ------------- | ------- | -------- | ------------------------------------------------- | ----------- |
| `owner`       | string  | **Yes**  | Owner login.                                      | `scanset`   |
| `repo`        | string  | **Yes**  | Repo name.                                        | `Endpoint-State-Policy` |
| `workflow_id` | integer | **Yes**  | Numeric workflow id (stable across file renames). | `276254256` |

---

## Commands Executed

```
GET https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow_id}
Headers:
  Authorization: Bearer <GITHUB_TOKEN>
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

**Requires PAT scope:** `Repository: Actions: Read`.

**Sample response (abbreviated):**

```json
{
  "id": 276254256,
  "node_id": "W_kwDOQNoQW84Qd04w",
  "name": "CI",
  "path": ".github/workflows/ci.yml",
  "state": "active",
  "created_at": "2026-05-13T13:16:09.000-06:00",
  "updated_at": "2026-05-13T13:16:09.000-06:00",
  "url": "https://api.github.com/repos/.../actions/workflows/276254256",
  "html_url": "https://github.com/.../blob/main/.github/workflows/ci.yml",
  "badge_url": "https://github.com/.../workflows/CI/badge.svg"
}
```

**Workflow `state` values** (per GitHub Actions docs):
- `active` — workflow runs on triggers
- `deleted` — workflow file removed; record retained
- `disabled_fork` — disabled because the repo is a fork
- `disabled_inactivity` — auto-disabled after 60 days of repo inactivity
- `disabled_manually` — explicitly disabled by an org/repo admin

---

## Collected Data Fields

| Field    | Type    | Always Present | Source                            |
| -------- | ------- | -------------- | --------------------------------- |
| `found`  | boolean | Yes            | `true` on HTTP 200                |
| `active` | boolean | When found     | `true` iff `state == "active"`    |
| `state`  | string  | When found     | `state`                           |
| `name`   | string  | When found     | `name` (workflow YAML's `name:`)  |
| `path`   | string  | When found     | `path` (e.g. `.github/workflows/ci.yml`) |

---

## State Fields

| State Field | Type    | Allowed Operations |
| ----------- | ------- | ------------------ |
| `found`     | boolean | `=`, `!=`          |
| `active`    | boolean | `=`, `!=`          |
| `state`     | string  | `=`, `!=`          |
| `name`      | string  | `=`, `!=`          |
| `path`      | string  | `=`, `!=`          |

---

## Failure Modes

| HTTP status | CTN behavior                                                            |
| ----------- | ----------------------------------------------------------------------- |
| 200         | All fields populated.                                                   |
| 401         | `CollectionError`.                                                      |
| 403         | `found=false`, PAT lacks `Actions: Read`.                               |
| 404         | `found=false`, workflow was deleted between discovery and scan.         |
| 5xx / 429   | Retry-with-backoff.                                                     |

---

## Collection Strategy

| Property                 | Value                                          |
| ------------------------ | ---------------------------------------------- |
| Collector ID             | `github_workflow_collector`                    |
| Collector Type           | `github_workflow`                              |
| Collection Mode          | Metadata                                       |
| Required Capabilities    | `github_pat_env`, `github_actions_read`        |
| Required Env Vars        | `GITHUB_TOKEN`, `GITHUB_BASE_URL` (optional)   |
| Expected Collection Time | ~300ms                                         |

---

## Relationship to the CI daemon OIDC enrollment

The numeric `workflow_id` returned by this CTN is the same value that
the proposed CI/CD daemon's OIDC SAN binds against. SAN shape:

```
scanset://ci/github-actions/repo/<owner>/<repo>/workflow/<file>/run/<run_id>
```

The asset metadata on `SDLC::Pipeline` carries `metadata.github_id` (numeric)
captured at discovery; this CTN reads the live record so the policy can
detect drift (e.g. workflow deleted but daemon still emits envelopes).
See `pathfinder/planning/discovery-github.md` for the full binding design.

---

## Control Mapping (sample)

This CTN surfaces facts; control mappings live in policies that consume it.
Useful checks include:
- `active = false` AND last activity > N days → operational hygiene
- `state = "disabled_inactivity"` → repo abandonment indicator
- `state = "disabled_manually"` → audit trail of who disabled CI
