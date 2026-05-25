# github_branch_protection

## Overview

Fetches `GET /repos/{owner}/{repo}/branches/{branch}/protection` and
surfaces the branch protection rule's fields as typed STATE. Distinct
from the other GitHub CTNs in that **three states are semantically
meaningful**, not just success/failure:

| HTTP status                                    | Interpretation                                                                          |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- |
| 200                                            | Protection rule configured. `protection_exists=true`, fields populated from response.   |
| 404 ("Branch not protected")                   | No protection rule on this branch. **A finding-worthy state, not an error.** `protection_exists=false`. |
| 403 ("Upgrade to GitHub Pro" / "Make this repository public") | Plan restriction — protection isn't available on this repo's plan. **Not a misconfig** (operator can't enable it here). `protection_exists=false`, `protection_plan_restricted=true`. |

ESP policies built on this CTN should N/A the "plan_restricted" case
rather than failing it. Policy authors get a typed boolean
(`protection_plan_restricted`) to branch on.

**Platform:** GitHub
**Collection Method:** Single authenticated HTTPS GET per object.
**Target asset_type:** `SDLC::Repository`

---

## Object Fields

| Field    | Type   | Required | Description                                                              | Example                  |
| -------- | ------ | -------- | ------------------------------------------------------------------------ | ------------------------ |
| `owner`  | string | **Yes**  | Owner login.                                                             | `scanset`                |
| `repo`   | string | **Yes**  | Repo name.                                                               | `Endpoint-State-Policy`  |
| `branch` | string | **Yes**  | Branch name to query protection for. Usually the repo's `default_branch`. | `main`                  |

---

## Commands Executed

```
GET https://api.github.com/repos/{owner}/{repo}/branches/{branch}/protection
Headers:
  Authorization: Bearer <GITHUB_TOKEN>
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

**Requires PAT scope:** `Repository: Administration: Read`.

**Sample 200 response (abbreviated, when protection is configured):**

```json
{
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": false
  },
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci/build", "ci/test"]
  },
  "enforce_admins": { "enabled": true },
  "required_signatures": { "enabled": true },
  "required_linear_history": { "enabled": false },
  "allow_force_pushes": { "enabled": false },
  "allow_deletions": { "enabled": false },
  "required_conversation_resolution": { "enabled": true },
  "lock_branch": { "enabled": false }
}
```

**Sample 404 response (no protection rule):**

```json
{
  "message": "Branch not protected",
  "documentation_url": "https://docs.github.com/rest/branches/branch-protection#get-branch-protection",
  "status": "404"
}
```

**Sample 403 response (plan restriction):**

```json
{
  "message": "Upgrade to GitHub Pro or make this repository public to enable this feature.",
  "documentation_url": "https://docs.github.com/rest/branches/branch-protection#get-branch-protection",
  "status": "403"
}
```

---

## Collected Data Fields

| Field                              | Type    | Always Present | Source                                                                                |
| ---------------------------------- | ------- | -------------- | ------------------------------------------------------------------------------------- |
| `found`                            | boolean | Yes            | HTTP call completed without unrecoverable error.                                       |
| `protection_exists`                | boolean | Yes            | `true` iff HTTP 200. `false` for 404 or 403-plan-restricted.                          |
| `protection_plan_restricted`       | boolean | Yes            | `true` iff HTTP 403 with a recognized plan-restriction message.                       |
| `required_pr_review_count`         | integer | Yes            | `required_pull_request_reviews.required_approving_review_count`, or `0` if absent.    |
| `dismiss_stale_reviews`            | boolean | Yes            | `required_pull_request_reviews.dismiss_stale_reviews`, or `false`.                    |
| `require_code_owner_reviews`       | boolean | Yes            | `required_pull_request_reviews.require_code_owner_reviews`, or `false`.               |
| `require_last_push_approval`       | boolean | Yes            | `required_pull_request_reviews.require_last_push_approval`, or `false`.               |
| `requires_signed_commits`          | boolean | Yes            | `required_signatures.enabled`, or `false`.                                            |
| `requires_linear_history`          | boolean | Yes            | `required_linear_history.enabled`, or `false`.                                        |
| `requires_conversation_resolution` | boolean | Yes            | `required_conversation_resolution.enabled`, or `false`.                              |
| `allows_force_pushes`              | boolean | Yes            | `allow_force_pushes.enabled`, or `false`. **`true` is bad.**                          |
| `allows_deletions`                 | boolean | Yes            | `allow_deletions.enabled`, or `false`. **`true` is bad.**                             |
| `enforces_admins`                  | boolean | Yes            | `enforce_admins.enabled`, or `false`. **`false` means admins bypass.**                |
| `required_status_checks_strict`    | boolean | Yes            | `required_status_checks.strict`, or `false`.                                          |
| `required_status_checks_count`     | integer | Yes            | `len(required_status_checks.contexts)`, or `0`.                                       |
| `lock_branch`                      | boolean | Yes            | `lock_branch.enabled`, or `false`.                                                    |

Note: when `protection_exists=false`, all the "rule detail" fields are
present but default to `0` / `false` so policy TEST blocks don't error
on missing fields. This is the "absent semantics" — easier for authors
to assert against than guarding for null.

---

## State Fields

All collected fields are addressable in ESP STATE assertions with the
operations on the right column:

| State Field                        | Type    | Allowed Operations          |
| ---------------------------------- | ------- | --------------------------- |
| `found`                            | boolean | `=`, `!=`                   |
| `protection_exists`                | boolean | `=`, `!=`                   |
| `protection_plan_restricted`       | boolean | `=`, `!=`                   |
| `required_pr_review_count`         | int     | `=`, `!=`, `<`, `<=`, `>`, `>=` |
| `dismiss_stale_reviews`            | boolean | `=`, `!=`                   |
| `require_code_owner_reviews`       | boolean | `=`, `!=`                   |
| `require_last_push_approval`       | boolean | `=`, `!=`                   |
| `requires_signed_commits`          | boolean | `=`, `!=`                   |
| `requires_linear_history`          | boolean | `=`, `!=`                   |
| `requires_conversation_resolution` | boolean | `=`, `!=`                   |
| `allows_force_pushes`              | boolean | `=`, `!=`                   |
| `allows_deletions`                 | boolean | `=`, `!=`                   |
| `enforces_admins`                  | boolean | `=`, `!=`                   |
| `required_status_checks_strict`    | boolean | `=`, `!=`                   |
| `required_status_checks_count`     | int     | `=`, `!=`, `<`, `<=`, `>`, `>=` |
| `lock_branch`                      | boolean | `=`, `!=`                   |

---

## Collection Strategy

| Property                 | Value                                                |
| ------------------------ | ---------------------------------------------------- |
| Collector ID             | `github_branch_protection_collector`                 |
| Collector Type           | `github_branch_protection`                           |
| Collection Mode          | Metadata                                             |
| Required Capabilities    | `github_pat_env`, `github_administration_read`       |
| Required Env Vars        | `GITHUB_TOKEN`, `GITHUB_BASE_URL` (optional)         |
| Expected Collection Time | ~400ms                                               |

---

## Control Mapping (sample)

| Field check                                                 | Control(s)                                |
| ----------------------------------------------------------- | ----------------------------------------- |
| `protection_exists = false AND protection_plan_restricted = false` | CMMC CM.L2-3.4.5, NIST CM-3 / CM-5  |
| `required_pr_review_count < 1`                              | CMMC CA.L2-3.12.1, NIST CA-2 / CM-4       |
| `requires_signed_commits = false`                           | CMMC SI.L2-3.14.1, NIST SI-7              |
| `allows_force_pushes = true`                                | NIST AU-9 / SI-7 (audit integrity)        |
| `enforces_admins = false`                                   | NIST AC-6 (least privilege at admin boundary) |
