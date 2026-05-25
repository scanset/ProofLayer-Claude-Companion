# linux_dpkg_package

## Overview

Debian/Ubuntu equivalent of `rpm_package`: validates installed state and
version of a package via `dpkg-query`. Backs CIS Ubuntu "Ensure `<pkg>` is
installed / is not installed" recommendations (§2.1 servers, §2.2 clients,
firewall/MAC package presence, etc.).

**Platform:** Ubuntu / Debian (Rocky/RHEL use `rpm_package`)
**Collection Method:** `dpkg-query -W` run on the target host
**Use Case:** Confirm unneeded software is absent, or a required package present.

---

## Object Fields (Input)

| Field          | Type   | Required | Description           | Example                |
| -------------- | ------ | -------- | --------------------- | ---------------------- |
| `package_name` | string | Yes      | Debian package name   | `openssh-server`, `telnet` |

---

## Collected Data Fields (Output)

| Field       | Type    | Required | Description                                            |
| ----------- | ------- | -------- | ------------------------------------------------------ |
| `found`     | boolean | Yes      | Whether the package state could be determined          |
| `installed` | boolean | No       | dpkg status is `installed`                             |
| `version`   | string  | No       | Installed version (only when installed)                |

> A package unknown to dpkg (`dpkg-query` exit ≠ 0) and a known-but-removed
> package (`not-installed`) both yield `installed = false`, `found = true`.

---

## State Fields (Validation)

| Field       | Type    | Operations            | Maps To     | Description              |
| ----------- | ------- | --------------------- | ----------- | ------------------------ |
| `found`     | boolean | `=`, `!=`             | `found`     | State determinable       |
| `installed` | boolean | `=`, `!=`             | `installed` | `false` asserts absence  |
| `version`   | string / evr_string | `=`, `!=`, `contains`, `>=`, `<=`, `>`, `<` | `version`   | Installed version. Ordering ops use Debian/EVR semantics (epoch:upstream-revision) — enables CVE "installed < fixed" checks, the same way rpm_package does. |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_dpkg_package` |
| Collection Mode | Metadata |
| Required Capabilities | `dpkg_access` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | No |
| Batch Collection | No |

---

## Channel Integration

Runs `dpkg-query` over the configured scan channel. Reads the
**target** host's package DB. Unprivileged — works as the SSH login user.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `dpkg-query -W -f='${db:Status-Status}	${Version}' <package>`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
dpkg-query -W -f='${db:Status-Status}\t${Version}' <package>
# installed:      "installed\t1:9.6p1-3ubuntu13"
# known, removed: "not-installed\t"
# unknown:        exit 1
```

Whitelisted: `dpkg-query` (`/usr/bin/dpkg-query`).

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Package must be absent (CIS §2.1/§2.2)

```esp
OBJECT pkg
    package_name `telnetd`
OBJECT_END

STATE absent
    installed boolean = false
STATE_END

CTN linux_dpkg_package
    TEST all all AND
    STATE_REF absent
    OBJECT_REF pkg
CTN_END
```

### Package must be installed

```esp
OBJECT pkg
    package_name `apparmor`
OBJECT_END

STATE present
    installed boolean = true
STATE_END

CTN linux_dpkg_package
    TEST all all AND
    STATE_REF present
    OBJECT_REF pkg
CTN_END
```

### CVE detection — flag if installed below the fixed version (CVE-2024-6387)

```esp
OBJECT pkg_check
    package_name `openssh-server`
OBJECT_END

STATE pkg_state
    installed boolean    = true
    version   evr_string >= `1:9.6p1-3ubuntu13.5`
STATE_END

CTN linux_dpkg_package
    TEST all all AND
    STATE_REF pkg_state
    OBJECT_REF pkg_check
CTN_END
```

PASS means the installed version is at or above the fix (patched); FAIL means the
host is below the fix (vulnerable). Mirrors the `rpm_package` CVE pattern. See
`esp/Ubuntu/CVE/`.

---

## CIS Coverage

| Benchmark        | Sections | Examples |
| ---------------- | -------- | -------- |
| CIS Ubuntu 24.04 | §2.1, §2.2, §1.3.1.1, §4.2.x | unneeded servers/clients absent; apparmor/ufw/nftables present |

---

## Error Conditions

| Condition                | Error Type         | Effect on TEST              |
| ------------------------ | ------------------ | --------------------------- |
| `dpkg-query` not found   | `CollectionFailed` | Error state                 |
| package unknown / removed | N/A               | `found` = true, `installed` = false |

---

## Related CTN Types

| CTN Type      | Relationship                          |
| ------------- | ------------------------------------- |
| `rpm_package` | Rocky/RHEL package-state equivalent   |
| `systemd_service` | Service enabled/active state for an installed package |
