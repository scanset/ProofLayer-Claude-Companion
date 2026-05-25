# linux_sshd_config

## Overview

Validates the **effective** OpenSSH server configuration via `sshd -T`, which
expands built-in defaults and `Match` blocks — i.e. the value the daemon
actually runs with, not merely what a `grep` of `sshd_config` would show. Backs
the CIS SSH section (Ciphers, MACs, KexAlgorithms, `ClientAliveInterval`,
`ClientAliveCountMax`, `PermitRootLogin`, `LoginGraceTime`, `MaxAuthTries`,
`Banner`, `MaxStartups`, …).

**Platform:** Linux (distro-agnostic — `sshd -T` identical on Rocky/Ubuntu)
**Collection Method:** `sshd -T` run on the target host
**Use Case:** SSH daemon hardening against the effective runtime config.

---

## Object Fields (Input)

| Field       | Type   | Required | Description                            | Example                              |
| ----------- | ------ | -------- | -------------------------------------- | ------------------------------------ |
| `parameter` | string | Yes      | sshd effective-config keyword (lower)  | `permitrootlogin`, `clientaliveinterval`, `ciphers` |

### Notes

- `sshd -T` emits all keywords lowercase; comparison is case-insensitive on the key.

---

## Collected Data Fields (Output)

| Field   | Type    | Required | Description                                              |
| ------- | ------- | -------- | -------------------------------------------------------- |
| `found` | boolean | Yes      | Whether the keyword was present in `sshd -T` output      |
| `value` | string  | No       | Effective value (multi-valued keywords space-joined)     |

---

## State Fields (Validation)

| Field   | Type    | Operations                          | Maps To | Description           |
| ------- | ------- | ----------------------------------- | ------- | --------------------- |
| `found` | boolean | `=`, `!=`                           | `found` | Keyword present       |
| `value` | string  | `=`, `!=`, `contains`, `not_contains` | `value` | Effective value       |

Use `not_contains` for "weak cipher must be absent" (e.g. `value not_contains \`cbc\``).

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_sshd_config` |
| Collection Mode | Metadata |
| Required Capabilities | `sshd_access` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | Yes |
| Batch Collection | No |

---

## Channel Integration

Runs `sshd -T` over the configured scan channel. A
`--channel ssh|aws-ssm|az-bastion` scan reads the **target** daemon's
effective config — never the scanner's own host.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `sshd -T`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
sshd -T          # effective config dump: "keyword value..." lines, lowercase keys
```

Whitelisted: `sshd`, `/usr/sbin/sshd`, `/sbin/sshd`.

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Root login disabled (CIS — PermitRootLogin)

```esp
OBJECT permit_root
    parameter `permitrootlogin`
OBJECT_END

STATE root_login_off
    found boolean = true
    value string = `no`
STATE_END

CTN linux_sshd_config
    TEST at_least_one all AND
    STATE_REF root_login_off
    OBJECT_REF permit_root
CTN_END
```

### Idle timeout configured (ClientAliveInterval ≤ 900, != 0 handled by policy)

```esp
OBJECT alive_interval
    parameter `clientaliveinterval`
OBJECT_END

STATE has_timeout
    found boolean = true
    value string not_contains `0`
STATE_END

CTN linux_sshd_config
    TEST at_least_one all AND
    STATE_REF has_timeout
    OBJECT_REF alive_interval
CTN_END
```

### Weak CBC ciphers must be absent

```esp
OBJECT ciphers
    parameter `ciphers`
OBJECT_END

STATE no_cbc
    found boolean = true
    value string not_contains `cbc`
STATE_END

CTN linux_sshd_config
    TEST at_least_one all AND
    STATE_REF no_cbc
    OBJECT_REF ciphers
CTN_END
```

---

## CIS Coverage

| Benchmark         | Section | Examples                                                  |
| ----------------- | ------- | --------------------------------------------------------- |
| CIS Rocky Linux 9 | 5.1.x   | Ciphers, MACs, KexAlgorithms, ClientAlive*, MaxAuthTries  |
| CIS Ubuntu 24.04  | 5.1.x   | sshd access, banner, login grace, max startups            |

> File-permission controls on `/etc/ssh/sshd_config` and host keys (CIS 5.1.1–5.1.3)
> route to `file_metadata`, not this CTN.

---

## Error Conditions

| Condition                | Error Type         | Effect on TEST  |
| ------------------------ | ------------------ | --------------- |
| `sshd` binary not found  | `CollectionFailed` | Error state     |
| `sshd -T` syntax failure | N/A                | `found` = false |
| keyword absent           | N/A                | `found` = false |

---

## Related CTN Types

| CTN Type       | Relationship                                         |
| -------------- | ---------------------------------------------------- |
| `file_metadata`| sshd_config / host-key file permissions (CIS 5.1.1–5.1.3) |
| `file_content` | static `sshd_config` grep when `sshd -T` unavailable |
