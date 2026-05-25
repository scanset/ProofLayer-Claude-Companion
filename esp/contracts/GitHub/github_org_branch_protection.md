# github_org_branch_protection

## Overview

Org-iterate sibling of [`github_branch_protection`](github_branch_protection.md). Lists every repository under `owner`, then runs the same `GET /repos/{owner}/{repo}/branches/{branch}/protection` call per repo and folds the results into a single aggregate verdict. A repo with no protection rule (404 "Branch not protected") counts as failing every per-flag aggregate — no rule means force-pushes, deletions, and admin bypass are all effectively allowed.

**Platform:** GitHub (server-side HTTPS to the REST API; no shell-out)
**Auth:** `GITHUB_TOKEN` + `GITHUB_BASE_URL` from a `GithubPat` credential (resolver-injected)
**Collection Method:** one `list-repos` call + one protection GET per repo, aggregated

---

## Object Fields

| Field              | Type    | Required | Description                                                              | Example   |
| ------------------ | ------- | -------- | ------------------------------------------------------------------------ | --------- |
| `owner`            | string  | **Yes**  | Org (or user) login whose repos are enumerated                           | `scanset` |
| `branch`           | string  | No       | Pinned branch to check on every repo. Omitted → each repo's `default_branch` | `main` |
| `include_archived` | boolean | No       | Include archived repos in the sweep (default `false`)                    | `false`   |
| `exclude`          | string  | No       | Comma-separated repo names to skip                                       | `legacy`  |

- `owner` is **required**; missing → `InvalidObjectConfiguration`.

---

## Commands Executed

### Command 1: list repos for owner

```
GET /orgs/{owner}/repos?per_page=100   (paginated; falls back to /users/{owner}/repos)
```

### Command 2 (per repo): branch protection

```
GET /repos/{owner}/{repo}/branches/{branch}/protection
```

`branch` is the pinned `branch` field when set, else the repo's `default_branch`. A `404 "Branch not protected"` is a *meaningful absence* — the repo is counted as unprotected (failing), not an error.

---

## Collected Data Fields

| Field                       | Type       | Always Present | Source                                                       |
| --------------------------- | ---------- | -------------- | ------------------------------------------------------------ |
| `found`                     | boolean    | Yes            | `true` if the repo list was retrieved                        |
| `repo_count`                | integer    | Yes            | Repos evaluated                                              |
| `all_protected`             | boolean    | Yes            | Every repo's target branch has a protection rule             |
| `all_enforce_admins`        | boolean    | Yes            | Every protection rule enforces admins                        |
| `all_blocks_force_push`     | boolean    | Yes            | Every protection rule blocks force pushes                    |
| `all_blocks_deletion`       | boolean    | Yes            | Every protection rule blocks branch deletion                 |
| `all_requires_pr_review`    | boolean    | Yes            | Every protection rule requires PR review                     |
| `all_requires_signatures`   | boolean    | Yes            | Every protection rule requires signed commits                |
| `failing_repos`             | RecordData | Yes            | List of repos (and the flag) that drove a fail               |

---

## State Fields

| State Field               | Type    | Allowed Operations | Description                                |
| ------------------------- | ------- | ------------------ | ------------------------------------------ |
| `found`                   | boolean | `=`, `!=`          | Repo list retrieved                        |
| `all_protected`           | boolean | `=`, `!=`          | All repos' default/pinned branch protected |
| `all_enforce_admins`      | boolean | `=`, `!=`          | All rules enforce admins                   |
| `all_blocks_force_push`   | boolean | `=`, `!=`          | All rules block force push                 |
| `all_blocks_deletion`     | boolean | `=`, `!=`          | All rules block deletion                   |
| `all_requires_pr_review`  | boolean | `=`, `!=`          | All rules require PR review                |
| `all_requires_signatures` | boolean | `=`, `!=`          | All rules require signed commits           |

`record` checks inspect `failing_repos`.

---

## Collection Strategy

| Property        | Value                              |
| --------------- | ---------------------------------- |
| Collector ID    | `github_org_branch_protection-collector` |
| Collector Type  | `github_org_branch_protection`     |
| Required PAT scope | `repo` (read) — repository + branch-protection read |
| Network Intensive | Yes (one call per repo)          |

---

## ESP Example

```esp
OBJECT org
    owner `scanset`
OBJECT_END

STATE all_repos_protected
    found boolean = true
    all_protected boolean = true
    all_enforce_admins boolean = true
STATE_END

CTN github_org_branch_protection
    TEST all all AND
    STATE_REF all_repos_protected
    OBJECT_REF org
CTN_END
```

---

## Related CTN Types

| CTN Type                   | Relationship                                                      |
| -------------------------- | ----------------------------------------------------------------- |
| `github_branch_protection` | Per-repo sibling — same protection GET, one repo at a time        |
| `github_org_repos_metadata`| Org-iterate sibling for repo security_and_analysis flags          |
