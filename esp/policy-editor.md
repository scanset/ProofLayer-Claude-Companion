# The ESP Policies Page — In-Product Editor & Versioning

The **ESP Policies** page (system-ui) is the in-product editor for the `.esp`
policy tree: browse it, **create** new policies, **edit** existing ones, and —
because every change is a **git commit** — view a file's **history** and
**roll back** when an edit goes wrong. It's the authoring surface that complements
the conceptual [writing-policies.md](writing-policies.md) and the registry/linking
tasks in [../admin/](../admin/README.md#4-policy-registry--scheduling).

> Where: system-ui → **ESP Policies**. The page reads and writes the same
> git-tracked `esp/` tree the scanner runs from. Routes are under
> `/api/esp-policies/*`.

---

## The model in one line

**The `esp/` tree is a git repository. Every create / edit / delete / rename is
a commit; history and rollback are just git.** That's what makes editing safe:
nothing is destructive, every prior version is recoverable by hash.

---

## Browsing

The sidebar is the **directory tree** of `.esp` files (mirroring the on-disk
layout); there's also a flat list. Select a file to **view** its raw content.
Per-file indicators flag drift (files changed since their last registry sync).
Reads come from `GET /api/esp-policies/tree` and `GET /api/esp-policies/{path}`.

## Creating a policy

**New** adds a *pending* (unsaved) file in the sidebar and opens the editor on a
blank document. Give it a path (e.g. `aws/my_check.esp`), write the policy
(`META` + `DEF` — see [language-reference.md](language-reference.md)), and
**Save**. That issues `POST /api/esp-policies/edit` `{ path, content }`, which
writes the file and makes the **first commit** for it.

## Editing a policy

**Edit** opens a GitHub-style editor — a textarea with a syntax-highlighted
**Preview** tab — and tracks an **unsaved/dirty** state as you type. **Save**
commits the change (`PUT /api/esp-policies/edit`). **Delete** (with a confirm)
removes the file and commits that too. Each commit is attributed to an
**author** (`X-Policy-Author: Name <email>`).

> **Save always commits — even if the policy won't compile.** After a write the
> server hot-reloads its in-memory policy map, but a syntax/compile error there
> is logged as a warning and **does not fail the save**. The commit is intentional:
> you get a recoverable checkpoint, and you fix forward or roll back. The catch
> is that the Save itself looks successful regardless, so **confirm a freshly
> edited policy actually runs** — Test-Scan it (see
> [../usage/workflows/scanning-and-evidence.md](../usage/workflows/scanning-and-evidence.md));
> a broken policy simply won't load into the engine until it compiles.

## History & rollback

This is the safety net the editor is built around.

**History** (per file) lists that file's commits — author, time, message —
from `GET /api/esp-policies/actions/history?path=…`. You can view the file's
exact content **at** any commit (`…/actions/at?path=…&hash=…`).

**Revert** restores a chosen commit's content as a **new commit**
(`POST /api/esp-policies/actions/revert` `{ path, commit_hash }`). It's a
*forward* revert — it doesn't erase history, it appends a commit that puts the
file back to the old content (and returns the new commit hash). This is the
"my edit failed, roll it back" path: open **History**, pick the last good
commit, **Revert**.

**Rollback sync** is a distinct, registry-aware undo. Bulk registration writes
commits prefixed `PolicySetSync:`; *rollback sync* finds a file's most recent
such commit and restores the file to that commit's **parent** — i.e. undoes what
the last sync changed. It can run across many selected files at once
(`POST /api/esp-policies/actions/rollback-sync-bulk` `{ paths[] }`), reporting
per-file results so one failure doesn't abort the rest. Refusals are explicit
(e.g. *no prior sync to roll back*, or *the sync is the repo's root commit*).

| Action | What it undoes | Scope | Endpoint |
|---|---|---|---|
| **Revert** | a file back to any prior commit's content | one file, one commit | `…/actions/revert` |
| **Rollback sync** | the most recent registry-sync change to a file | one or many files | `…/actions/rollback-sync-bulk` |

---

## How it relates to the registry

Editing the file and **registering** it are two steps. The Policies page writes
and versions the `.esp` *file*; the **registry** (`bulk-register`, retire — see
[../admin/](../admin/README.md#4-policy-registry--scheduling)) is what makes a
policy available to bind to assets and scan. After editing, re-register so the
registry picks up the new content, then link/scan as usual.

---

## Alpha notes

- Author attribution comes from the editor; with the single super-admin model it
  isn't a per-user identity yet.
- The editor commits to the container's local git repo inside the `esp/` tree —
  versioning is local to the instance (it travels with the volume; see
  [../ops/](../ops/README.md#4-backup--restore)). There's no remote/push.
- Saving doesn't block on compile errors (above) — treat **Test-Scan** as your
  validation step, and **History → Revert** as your undo.

Related: [writing-policies.md](writing-policies.md) (how to author the content),
[language-reference.md](language-reference.md),
[errors-and-gotchas.md](errors-and-gotchas.md) (why a save might not compile).
