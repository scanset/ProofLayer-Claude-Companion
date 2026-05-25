# github_org_repos_metadata

## Overview

Org-iterate sibling of [`github_repo_metadata`](github_repo_metadata.md). Lists every repository under `owner`, then runs the same `GET /repos/{owner}/{repo}` call per repo to read the `security_and_analysis` block, and folds the results into a single aggregate verdict plus a `failing_repos` list so operators see which repos drove a fail.

**Platform:** GitHub (server-side HTTPS to the REST API; no shell-out)
**Auth:** `GITHUB_TOKEN` + `GITHUB_BASE_URL` from a `GithubPat` credential (resolver-injected)
**Collection Method:** one `list-repos` call + one metadata GET per repo, aggregated

---

## Object Fields

| Field              | Type    | Required | Description                                           | Example   |
| ------------------ | ------- | -------- | ----------------------------------------------------- | --------- |
| `owner`            | string  | **Yes**  | Org (or user) login whose repos are enumerated        | `scanset` |
| `include_archived` | boolean | No       | Include archived repos in the sweep (default `false`) | `false`   |
| `exclude`          | string  | No       | Comma-separated repo names to skip                    | `legacy`  |

- `owner` is **required**; missing → `InvalidObjectConfiguration`.

---

## Commands Executed

### Command 1: list repos for owner

```
GET /orgs/{owner}/repos?per_page=100   (paginated; falls back to /users/{owner}/repos)
```

### Command 2 (per repo): repo metadata

```
GET /repos/{owner}/{repo}
```

Reads `security_and_analysis.{secret_scanning, secret_scanning_push_protection, dependabot_security_updates}` and `web_commit_signoff_required` per repo.

---

## Collected Data Fields

| Field                                | Type       | Always Present | Source                                                |
| ------------------------------------ | ---------- | -------------- | ----------------------------------------------------- |
| `found`                              | boolean    | Yes            | `true` if the repo list was retrieved                 |
| `repo_count`                         | integer    | Yes            | Repos evaluated                                       |
| `all_secret_scanning_enabled`        | boolean    | Yes            | Every repo has secret scanning enabled                |
| `all_push_protection_enabled`        | boolean    | Yes            | Every repo has secret-scanning push protection        |
| `all_dependabot_updates_enabled`     | boolean    | Yes            | Every repo has Dependabot security updates            |
| `all_web_commit_signoff_required`    | boolean    | Yes            | Every repo requires web-UI commit signoff             |
| `failing_repos`                      | RecordData | Yes            | Repos (and the flag) that drove a fail                |

---

## State Fields

| State Field                       | Type    | Allowed Operations | Description                          |
| --------------------------------- | ------- | ------------------ | ------------------------------------ |
| `found`                           | boolean | `=`, `!=`          | Repo list retrieved                  |
| `all_secret_scanning_enabled`     | boolean | `=`, `!=`          | All repos secret-scanning on         |
| `all_push_protection_enabled`     | boolean | `=`, `!=`          | All repos push-protection on         |
| `all_dependabot_updates_enabled`  | boolean | `=`, `!=`          | All repos Dependabot updates on      |
| `all_web_commit_signoff_required` | boolean | `=`, `!=`          | All repos require web commit signoff |

`record` checks inspect `failing_repos`.

---

## Collection Strategy

| Property        | Value                                |
| --------------- | ------------------------------------ |
| Collector ID    | `github_org_repos_metadata-collector`|
| Collector Type  | `github_org_repos_metadata`          |
| Required PAT scope | `repo` (read) — repository metadata + security_and_analysis |
| Network Intensive | Yes (one call per repo)            |

---

## ESP Example

```esp
OBJECT org
    owner `scanset`
OBJECT_END

STATE all_repos_secure
    found boolean = true
    all_secret_scanning_enabled boolean = true
    all_dependabot_updates_enabled boolean = true
STATE_END

CTN github_org_repos_metadata
    TEST all all AND
    STATE_REF all_repos_secure
    OBJECT_REF org
CTN_END
```

---

## Related CTN Types

| CTN Type                       | Relationship                                              |
| ------------------------------ | --------------------------------------------------------- |
| `github_repo_metadata`         | Per-repo sibling — same metadata GET, one repo at a time  |
| `github_org_branch_protection` | Org-iterate sibling for branch-protection rules           |
