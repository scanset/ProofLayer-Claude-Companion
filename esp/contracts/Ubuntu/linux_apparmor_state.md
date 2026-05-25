# linux_apparmor_state

## Overview

Validates AppArmor posture via `apparmor_status` — profiles loaded, in enforce
mode, in complain mode, and unconfined processes. Backs CIS Ubuntu **§1.3
(AppArmor)** recommendations: profiles loaded, in enforce/complain, enforcing.

**Platform:** Ubuntu (Rocky/RHEL use `linux_selinux_state`)
**Collection Method:** `apparmor_status` run on the target host
**Use Case:** Confirm mandatory access control profiles are loaded and enforcing.

---

## Object Fields (Input)

| Field           | Type   | Required | Description                              | Example   |
| --------------- | ------ | -------- | ---------------------------------------- | --------- |
| `expected_mode` | string | No       | Documentation hint only (not used by collector) | `enforce` |

> Singleton check — no required object fields. Assert the desired counts via STATE.

---

## Collected Data Fields (Output)

| Field                  | Type    | Required | Description                                  |
| ---------------------- | ------- | -------- | -------------------------------------------- |
| `found`                | boolean | Yes      | Whether AppArmor tooling ran (`apparmor_status`) |
| `profiles_loaded`      | integer | No       | Total profiles loaded                        |
| `profiles_enforce`     | integer | No       | Profiles in enforce mode                     |
| `profiles_complain`    | integer | No       | Profiles in complain mode                    |
| `processes_unconfined` | integer | No       | Processes with a profile defined but unconfined |

---

## State Fields (Validation)

| Field                  | Type    | Operations                      | Maps To                | Description          |
| ---------------------- | ------- | ------------------------------- | ---------------------- | -------------------- |
| `found`                | boolean | `=`, `!=`                       | `found`                | Tooling ran          |
| `profiles_loaded`      | integer | `=`, `!=`, `>`, `>=`, `<`, `<=` | `profiles_loaded`      | Loaded count         |
| `profiles_enforce`     | integer | `=`, `!=`, `>`, `>=`, `<`, `<=` | `profiles_enforce`     | Enforce count        |
| `profiles_complain`    | integer | `=`, `!=`, `>`, `>=`, `<`, `<=` | `profiles_complain`    | Complain count       |
| `processes_unconfined` | integer | `=`, `!=`, `>`, `>=`, `<`, `<=` | `processes_unconfined` | Unconfined count     |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_apparmor_state` |
| Collection Mode | Metadata |
| Required Capabilities | `apparmor_tools` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | Yes |
| Batch Collection | No |

---

## Channel Integration

Runs `apparmor_status` over the configured scan channel.
Reads the **target** host's AppArmor state. **Privileged:** without root,
`apparmor_status` prints "You do not have enough privilege to read the profile
set" and the counts read as 0 — run with a root-capable credential (or
sudo-wrapped execution) for accurate counts.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `apparmor_status`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
apparmor_status
# "188 profiles are loaded."
# "111 profiles are in enforce mode."
# "0 profiles are in complain mode."
# "0 processes are unconfined but have a profile defined."
```

The collector parses the leading integer of each labelled line. Whitelisted:
`apparmor_status`, `aa-status`.

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Profiles loaded and in enforce or complain (CIS 1.3.1.3)

```esp
OBJECT aa
    expected_mode `enforce`
OBJECT_END

STATE loaded
    found boolean = true
    profiles_loaded int > 0
STATE_END

CTN linux_apparmor_state
    TEST all all AND
    STATE_REF loaded
    OBJECT_REF aa
CTN_END
```

### All profiles enforcing (CIS 1.3.1.4)

```esp
OBJECT aa
    expected_mode `enforce`
OBJECT_END

STATE enforcing
    found boolean = true
    profiles_loaded int > 0
    profiles_complain int = 0
STATE_END

CTN linux_apparmor_state
    TEST all all AND
    STATE_REF enforcing
    OBJECT_REF aa
CTN_END
```

---

## CIS Coverage

| Benchmark        | Section | Notes |
| ---------------- | ------- | ----- |
| CIS Ubuntu 24.04 | §1.3.1.3 (loaded, enforce/complain), §1.3.1.4 (enforcing) | 1.3.1.1 (installed) → `linux_dpkg_package` apparmor; 1.3.1.2 (bootloader `apparmor=1`) → `grub_config`/`file_content` |

---

## Error Conditions

| Condition                   | Error Type         | Effect on TEST          |
| --------------------------- | ------------------ | ----------------------- |
| `apparmor_status` not found | `CollectionFailed` | Error state             |
| not root                    | N/A                | counts read 0           |

---

## Related CTN Types

| CTN Type               | Relationship                        |
| ---------------------- | ----------------------------------- |
| `linux_selinux_state`  | Rocky/RHEL MAC equivalent           |
| `linux_dpkg_package`   | apparmor package installed          |
| `grub_config` / `file_content` | `apparmor=1` bootloader parameter |
