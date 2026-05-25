# linux_selinux_state

## Overview

Validates the running and configured SELinux posture via `getenforce` (current
mode) and `sestatus` (loaded policy + mode-from-config). Backs the CIS
Rocky/RHEL **§1.3 MAC** recommendations: SELinux installed, not disabled,
policy configured, mode not disabled, mode enforcing.

**Platform:** Rocky / RHEL (Ubuntu uses AppArmor — see `linux_apparmor_state`)
**Collection Method:** `getenforce` + `sestatus` run on the target host
**Use Case:** Confirm mandatory access control is active and enforcing.

---

## Object Fields (Input)

| Field           | Type   | Required | Description                                  | Example      |
| --------------- | ------ | -------- | -------------------------------------------- | ------------ |
| `expected_mode` | string | No       | Documentation hint only (not used by collector) | `enforcing` |

> Singleton check — no required object fields. Assert the desired state via STATE.

---

## Collected Data Fields (Output)

| Field           | Type    | Required | Description                                              |
| --------------- | ------- | -------- | -------------------------------------------------------- |
| `found`         | boolean | Yes      | Whether SELinux tooling is present (`getenforce` ran)    |
| `current_mode`  | string  | No       | Running mode (lowercased): `enforcing`/`permissive`/`disabled` |
| `config_mode`   | string  | No       | Mode from `/etc/selinux/config` (via `sestatus`)         |
| `loaded_policy` | string  | No       | Loaded policy name (e.g. `targeted`)                     |

---

## State Fields (Validation)

| Field           | Type    | Operations            | Maps To         | Description           |
| --------------- | ------- | --------------------- | --------------- | --------------------- |
| `found`         | boolean | `=`, `!=`             | `found`         | SELinux tooling present |
| `current_mode`  | string  | `=`, `!=`, `contains` | `current_mode`  | Running mode          |
| `config_mode`   | string  | `=`, `!=`, `contains` | `config_mode`   | Configured mode       |
| `loaded_policy` | string  | `=`, `!=`, `contains` | `loaded_policy` | Loaded policy name    |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_selinux_state` |
| Collection Mode | Metadata |
| Required Capabilities | `selinux_tools` |
| Expected Collection Time | ~30ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | No |
| Batch Collection | No |

---

## Channel Integration

Runs `getenforce` then `sestatus` over the configured scan channel. A
`--channel ssh|aws-ssm|az-bastion` scan reads the **target** host — never the
scanner's own host.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `getenforce ; sestatus`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
getenforce          # Enforcing | Permissive | Disabled
sestatus            # "Loaded policy name: targeted", "Mode from config file: enforcing"
```

If `getenforce` is absent/non-zero, SELinux tooling is treated as not present
(`found = false`). `sestatus` enriches with policy + config mode; if it fails,
the `getenforce` result is still returned.

Whitelisted: `getenforce`, `sestatus` (sbin/bin paths).

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Mode not disabled (CIS 1.3.1.4)

```esp
OBJECT selinux
    expected_mode `not_disabled`
OBJECT_END

STATE not_disabled
    found boolean = true
    current_mode string != `disabled`
STATE_END

CTN linux_selinux_state
    TEST all all AND
    STATE_REF not_disabled
    OBJECT_REF selinux
CTN_END
```

### Mode enforcing (CIS 1.3.1.5)

```esp
OBJECT selinux
    expected_mode `enforcing`
OBJECT_END

STATE enforcing
    found boolean = true
    current_mode string = `enforcing`
STATE_END

CTN linux_selinux_state
    TEST all all AND
    STATE_REF enforcing
    OBJECT_REF selinux
CTN_END
```

---

## CIS Coverage

| Benchmark         | Section | Notes |
| ----------------- | ------- | ----- |
| CIS Rocky Linux 9 | 1.3.1.4 (mode not disabled), 1.3.1.5 (enforcing), 1.3.1.3 (policy via `loaded_policy`) | 1.3.1.1 (installed) → `rpm_package` libselinux; 1.3.1.2 (bootloader) → `grub_config`/`file_content` |

---

## Error Conditions

| Condition                  | Error Type         | Effect on TEST           |
| -------------------------- | ------------------ | ------------------------ |
| `getenforce` not found     | N/A                | `found` = false          |
| channel/exec failure       | `CollectionFailed` | Error state              |

---

## Related CTN Types

| CTN Type       | Relationship                                            |
| -------------- | ------------------------------------------------------- |
| `rpm_package`  | SELinux/mcstrans/setroubleshoot package presence (§1.3.1.1/1.3.1.7/1.3.1.8) |
| `grub_config` / `file_content` | `selinux=0`/`enforcing=0` absent from bootloader (§1.3.1.2) |
| `linux_apparmor_state` | Ubuntu MAC equivalent                          |
