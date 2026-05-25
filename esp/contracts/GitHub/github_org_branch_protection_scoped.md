# github_org_branch_protection_scoped

## Overview

Scoped-injection variant of [`github_org_branch_protection`](github_org_branch_protection.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `SDLC::Organization` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `github_org_branch_protection_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `owner` | `metadata.login` | **Yes** |

`target_asset_type`: `SDLC::Organization`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET organizations union
    OBJECT t
        target `SDLC::Organization`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

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

---

## Scoped ESP Policy Example

```esp
DEF
    SET github_orgs union
        OBJECT t
            target `SDLC::Organization`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE org_all_main_branches_block_deletion
        found boolean = true
        all_blocks_deletions boolean = true
    STATE_END

    CRI AND
        CTN github_org_branch_protection_scoped
            TEST all all AND
            STATE_REF org_all_main_branches_block_deletion
            SET_REF github_orgs
        CTN_END
    CRI_END
DEF_END
```

