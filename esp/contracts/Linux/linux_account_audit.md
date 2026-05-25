# linux_account_audit

## Overview

Parameterized structural audits over `/etc/passwd`, `/etc/shadow`, and
`/etc/group` that cannot be expressed as a single `file_content` grep —
duplicate UID/GID/name detection, empty-password detection, non-root UID 0,
and password-delegated-to-shadow checks. Backs CIS section 7 ("Users and
Groups") automated recommendations.

**Platform:** Linux (distro-agnostic)
**Collection Method:** read-only `cat` of /etc/passwd|/etc/shadow|/etc/group run on the target host
**Use Case:** Account-database integrity checks requiring full-file parsing.

---

## Value-Plane Discipline (Non-Goal)

When the `empty_password` check reads `/etc/shadow`, the collector tests only
the **shape** of the password field (empty vs not) and emits the affected
**usernames** — it **never** reads, stores, or emits the password hash itself.
No other secret/value-plane material is surfaced. This honors the CTN
read-only invariant (metadata about shape is fine; secret values are not).

---

## Object Fields (Input)

| Field   | Type   | Required | Description                | Example           |
| ------- | ------ | -------- | -------------------------- | ----------------- |
| `check` | string | Yes      | Named account audit to run | `empty_password`  |

### Supported checks

| `check`               | Source         | Violation = entry where…                          | CIS theme               |
| --------------------- | -------------- | ------------------------------------------------- | ----------------------- |
| `empty_password`      | `/etc/shadow`  | password field is empty                           | no empty passwords      |
| `uid_zero`            | `/etc/passwd`  | UID 0 and username ≠ root                          | only root has UID 0     |
| `shadowed_passwords`  | `/etc/passwd`  | password field ≠ `x`                              | passwords in shadow     |
| `duplicate_uid`       | `/etc/passwd`  | UID appears more than once                         | unique UIDs             |
| `duplicate_user`      | `/etc/passwd`  | username appears more than once                    | unique usernames        |
| `duplicate_gid`       | `/etc/group`   | GID appears more than once                         | unique GIDs             |
| `duplicate_group`     | `/etc/group`   | group name appears more than once                  | unique group names      |

---

## Collected Data Fields (Output)

| Field             | Type    | Required | Description                                              |
| ----------------- | ------- | -------- | -------------------------------------------------------- |
| `found`           | boolean | Yes      | Whether the audit ran (source file readable)             |
| `compliant`       | boolean | No       | `true` iff `violation_count == 0`                        |
| `violation_count` | integer | No       | Number of offending entries                              |
| `details`         | string  | No       | Comma-joined offending identifiers (usernames/UIDs/GIDs — never hashes) |

---

## State Fields (Validation)

| Field             | Type    | Operations                          | Maps To           | Description              |
| ----------------- | ------- | ----------------------------------- | ----------------- | ------------------------ |
| `found`           | boolean | `=`, `!=`                           | `found`           | Audit executed           |
| `compliant`       | boolean | `=`, `!=`                           | `compliant`       | Zero violations          |
| `violation_count` | integer | `=`, `!=`, `>`, `>=`, `<`, `<=`     | `violation_count` | Offender count           |
| `details`         | string  | `=`, `!=`, `contains`, `not_contains` | `details`       | Offending identifiers    |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_account_audit` |
| Collection Mode | Metadata |
| Required Capabilities | `passwd_shadow_read` |
| Expected Collection Time | ~30ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | Yes |
| Batch Collection | No |

---

## Channel Integration

Reads source files via read-only `cat` run over the configured scan channel.
A `--channel ssh|aws-ssm|az-bastion` scan parses the **target** host's account
database — never the scanner's own host.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `cat <source-file> (<check>)`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
cat /etc/shadow      # empty_password
cat /etc/passwd      # uid_zero, shadowed_passwords, duplicate_uid, duplicate_user
cat /etc/group       # duplicate_gid, duplicate_group
```

Whitelisted: `cat`, `/usr/bin/cat`, `/bin/cat` (read-only).

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### No accounts have an empty password (CIS 7.2.x)

```esp
OBJECT empty_pw
    check `empty_password`
OBJECT_END

STATE none_empty
    found boolean = true
    compliant boolean = true
STATE_END

CTN linux_account_audit
    TEST all all AND
    STATE_REF none_empty
    OBJECT_REF empty_pw
CTN_END
```

### Only root has UID 0

```esp
OBJECT uid0
    check `uid_zero`
OBJECT_END

STATE only_root
    found boolean = true
    violation_count int = 0
STATE_END

CTN linux_account_audit
    TEST all all AND
    STATE_REF only_root
    OBJECT_REF uid0
CTN_END
```

### No duplicate UIDs

```esp
OBJECT dup_uid
    check `duplicate_uid`
OBJECT_END

STATE unique
    found boolean = true
    compliant boolean = true
STATE_END

CTN linux_account_audit
    TEST all all AND
    STATE_REF unique
    OBJECT_REF dup_uid
CTN_END
```

---

## CIS Coverage

| Benchmark         | Section | Examples                                                          |
| ----------------- | ------- | ----------------------------------------------------------------- |
| CIS Rocky Linux 9 | 7.2.x   | no empty passwords, UID 0 = root only, no duplicate UID/GID/name, passwords shadowed |
| CIS Ubuntu 24.04  | 7.2.x   | same families                                                     |

> File-permission controls on `/etc/passwd`, `/etc/shadow`, `/etc/group`
> (e.g. mode/owner) route to `file_metadata`. Password-aging policy in
> `/etc/login.defs` routes to `file_content`; per-user `chage` aging is a
> future extension of this CTN.

---

## Error Conditions

| Condition                  | Error Type         | Effect on TEST          |
| -------------------------- | ------------------ | ----------------------- |
| source file unreadable     | N/A                | `found` = false         |
| `cat` not found / channel error | `CollectionFailed` | Error state        |
| unknown `check` value      | `InvalidObjectConfiguration` | Config error  |

---

## Related CTN Types

| CTN Type        | Relationship                                                |
| --------------- | ----------------------------------------------------------- |
| `file_metadata` | permissions/ownership on `/etc/passwd`, `/etc/shadow`, `/etc/group` |
| `file_content`  | `/etc/login.defs` aging defaults, PAM password policy       |
