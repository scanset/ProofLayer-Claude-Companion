# linux_auditd_rule

## Overview

Validates that a normalized audit rule is present in the **loaded** ruleset via
`auditctl -l` — the rules active in the running kernel, which may differ from
the on-disk `/etc/audit/rules.d/*.rules`. Backs the CIS audit section
recommendations that require specific watches/syscalls to be active (identity
changes, sudoers, time changes, login/logout records, MAC policy, module
load/unload, privileged-command execution, …).

**Platform:** Linux (distro-agnostic — `auditctl` identical on Rocky/Ubuntu)
**Collection Method:** `auditctl -l` run on the target host
**Use Case:** Verifying the audit subsystem is actively monitoring the events a
benchmark requires.

---

## Object Fields (Input)

| Field   | Type   | Required | Description                                  | Example                       |
| ------- | ------ | -------- | -------------------------------------------- | ----------------------------- |
| `match` | string | Yes      | Substring a loaded rule must contain         | `-w /etc/sudoers`, `-k identity`, `-S execve` |

### Notes

- Compared against each `auditctl -l` line; the first containing line is recorded.
- Use a key (`-k <name>`) or a watch path/syscall fragment as the match.

---

## Collected Data Fields (Output)

| Field         | Type    | Required | Description                                       |
| ------------- | ------- | -------- | ------------------------------------------------- |
| `found`       | boolean | Yes      | Whether any loaded rule contains the match        |
| `rule`        | string  | No       | The first matching loaded rule line (evidence)    |
| `match_count` | integer | No       | Number of loaded rules containing the match       |

---

## State Fields (Validation)

| Field         | Type    | Operations                          | Maps To       | Description              |
| ------------- | ------- | ----------------------------------- | ------------- | ------------------------ |
| `found`       | boolean | `=`, `!=`                           | `found`       | Matching rule present    |
| `rule`        | string  | `=`, `!=`, `contains`, `not_contains` | `rule`        | Matched rule line        |
| `match_count` | integer | `=`, `!=`, `>`, `>=`, `<`, `<=`     | `match_count` | Count of matching rules  |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_auditd_rule` |
| Collection Mode | Metadata |
| Required Capabilities | `auditctl_access` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | Yes |
| Batch Collection | No |

---

## Channel Integration

Runs `auditctl -l` over the configured scan channel. The loaded ruleset
inspected is the **target** host's — never the scanner's own host.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `auditctl -l`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
auditctl -l      # one normalized rule per line; "No rules" when empty
```

Whitelisted: `auditctl`, `/usr/sbin/auditctl`, `/sbin/auditctl`, plus
`augenrules` paths for future on-disk-vs-loaded comparison.

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Sudoers changes are watched with the scope key (CIS)

```esp
OBJECT sudoers_watch
    match `-w /etc/sudoers`
OBJECT_END

STATE watched_with_key
    found boolean = true
    rule string contains `-k`
STATE_END

CTN linux_auditd_rule
    TEST at_least_one all AND
    STATE_REF watched_with_key
    OBJECT_REF sudoers_watch
CTN_END
```

### Identity files watched (at least one rule keyed `identity`)

```esp
OBJECT identity
    match `-k identity`
OBJECT_END

STATE present
    found boolean = true
    match_count int >= 1
STATE_END

CTN linux_auditd_rule
    TEST at_least_one all AND
    STATE_REF present
    OBJECT_REF identity
CTN_END
```

---

## CIS Coverage

| Benchmark         | Section | Examples                                                       |
| ----------------- | ------- | -------------------------------------------------------------- |
| CIS Rocky Linux 9 | 6.3.x   | identity, sudoers, time-change, logins, MAC, module load/unload |
| CIS Ubuntu 24.04  | 6.2.x   | same watch/syscall families                                    |

> On-disk persistence (`/etc/audit/rules.d/*.rules`) and `auditd` package/service
> state pair with `file_content`, `rpm_package`/`dpkg_package`, and
> `systemd_service` respectively.

---

## Error Conditions

| Condition                   | Error Type         | Effect on TEST          |
| --------------------------- | ------------------ | ----------------------- |
| `auditctl` not found        | `CollectionFailed` | Error state             |
| permission denied / no auditd | N/A              | `found` = false, `match_count` = 0 |
| no matching rule loaded     | N/A                | `found` = false         |

---

## Related CTN Types

| CTN Type          | Relationship                                            |
| ----------------- | ------------------------------------------------------- |
| `file_content`    | on-disk `/etc/audit/rules.d/*.rules` and `auditd.conf`  |
| `systemd_service` | `auditd.service` enabled/active                         |
| `rpm_package` / `dpkg_package` | `audit` / `auditd` package installed       |
