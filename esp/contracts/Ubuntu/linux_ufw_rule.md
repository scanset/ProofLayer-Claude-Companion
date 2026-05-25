# linux_ufw_rule

## Overview

Validates the Uncomplicated Firewall posture via `ufw status verbose` — enabled
state, default policies, and individual rules. Backs CIS Ubuntu **§4.2 (ufw)**
recommendations.

**Platform:** Ubuntu (Rocky/RHEL use `firewalld_rule`; see also `linux_nftables_rule`)
**Collection Method:** `ufw status verbose` run on the target host
**Use Case:** Confirm the host firewall is active with the expected default
policy and rules.

---

## Object Fields (Input)

| Field   | Type   | Required | Description                              | Example                  |
| ------- | ------ | -------- | ---------------------------------------- | ------------------------ |
| `match` | string | Yes      | Substring a `ufw status verbose` line must contain | `Status: active`, `deny (incoming)` |

---

## Collected Data Fields (Output)

| Field         | Type    | Required | Description                                |
| ------------- | ------- | -------- | ------------------------------------------ |
| `found`       | boolean | Yes      | Any output line contains the match         |
| `line`        | string  | No       | First matching line (evidence)             |
| `match_count` | integer | No       | Number of matching lines                   |

---

## State Fields (Validation)

| Field         | Type    | Operations                          | Maps To       | Description           |
| ------------- | ------- | ----------------------------------- | ------------- | --------------------- |
| `found`       | boolean | `=`, `!=`                           | `found`       | Match present         |
| `line`        | string  | `=`, `!=`, `contains`, `not_contains` | `line`        | Matched line          |
| `match_count` | integer | `=`, `!=`, `>`, `>=`, `<`, `<=`     | `match_count` | Count of matches      |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_ufw_rule` |
| Collection Mode | Metadata |
| Required Capabilities | `ufw_access` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | Yes |
| Batch Collection | No |

---

## Channel Integration

Runs `ufw status verbose` over the configured scan channel.
Reads the **target** host's firewall. **Privileged:** `ufw status` requires
root — a non-root scan returns `found = false`. Run with a root-capable
credential (or sudo-wrapped execution) for accurate results.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `ufw status verbose`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
ufw status verbose
# "Status: active"
# "Default: deny (incoming), allow (outgoing), disabled (routed)"
# "22/tcp                     ALLOW IN    Anywhere"
```

Whitelisted: `ufw` (`/usr/sbin/ufw`).

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Default deny incoming (CIS 4.2.7)

```esp
OBJECT target
    match `deny (incoming)`
OBJECT_END

STATE present
    found boolean = true
STATE_END

CTN linux_ufw_rule
    TEST all all AND
    STATE_REF present
    OBJECT_REF target
CTN_END
```

---

## CIS Coverage

| Benchmark        | Section | Notes |
| ---------------- | ------- | ----- |
| CIS Ubuntu 24.04 | §4.2.x  | ufw active, default deny, loopback, per-port rules. (ufw *installed* → `linux_dpkg_package`; ufw *service enabled* → `systemd_service`.) |

---

## Error Conditions

| Condition                  | Error Type         | Effect on TEST          |
| -------------------------- | ------------------ | ----------------------- |
| `ufw` not found            | `CollectionFailed` | Error state             |
| not root / ufw inactive    | N/A                | `found` = false         |

---

## Related CTN Types

| CTN Type             | Relationship                              |
| -------------------- | ----------------------------------------- |
| `linux_nftables_rule`| nftables backend (mutually exclusive use) |
| `linux_dpkg_package` | ufw package installed                     |
| `firewalld_rule`     | Rocky/RHEL host-firewall equivalent       |
