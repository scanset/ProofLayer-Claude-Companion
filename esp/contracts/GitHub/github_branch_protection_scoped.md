# github_branch_protection_scoped

## Overview

Scoped-injection variant of [`github_branch_protection`](github_branch_protection.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `SDLC::Repository` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `github_branch_protection_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `owner` | `metadata.owner_login` | **Yes** |
| `repo` | `metadata.name` | **Yes** |
| `branch` | `metadata.default_branch` | **Yes** |

`target_asset_type`: `SDLC::Repository`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET repositorys union
    OBJECT t
        target `SDLC::Repository`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

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

---

## Scoped ESP Policy Example

```esp
DEF
    SET github_repos union
        OBJECT t
            target `SDLC::Repository`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE protection_requires_signed
        found boolean = true
        protection_exists boolean = true
        requires_signed_commits boolean = true
    STATE_END

    CRI AND
        CTN github_branch_protection_scoped
            TEST all all AND
            STATE_REF protection_requires_signed
            SET_REF github_repos
        CTN_END
    CRI_END
DEF_END
```

