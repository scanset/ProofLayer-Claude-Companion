# linux_nftables_rule

## Overview

Validates the loaded nftables ruleset via `nft list ruleset` — tables, base
chains, loopback handling, default policies, established/related acceptance.
Backs CIS Ubuntu **§4.3 (nftables)** recommendations.

**Platform:** Ubuntu (firewall backend; see also `linux_ufw_rule`)
**Collection Method:** `nft list ruleset` run on the target host
**Use Case:** Confirm an nftables ruleset with the expected tables/chains/policy.

---

## Object Fields (Input)

| Field   | Type   | Required | Description                              | Example                       |
| ------- | ------ | -------- | ---------------------------------------- | ----------------------------- |
| `match` | string | Yes      | Substring a `nft list ruleset` line must contain | `table inet`, `hook input`, `policy drop` |

---

## Collected Data Fields (Output)

| Field         | Type    | Required | Description                                |
| ------------- | ------- | -------- | ------------------------------------------ |
| `found`       | boolean | Yes      | Any ruleset line contains the match        |
| `line`        | string  | No       | First matching ruleset line (evidence)     |
| `match_count` | integer | No       | Number of matching lines                   |

---

## State Fields (Validation)

| Field         | Type    | Operations                          | Maps To       | Description           |
| ------------- | ------- | ----------------------------------- | ------------- | --------------------- |
| `found`       | boolean | `=`, `!=`                           | `found`       | Match present         |
| `line`        | string  | `=`, `!=`, `contains`, `not_contains` | `line`        | Matched ruleset line  |
| `match_count` | integer | `=`, `!=`, `>`, `>=`, `<`, `<=`     | `match_count` | Count of matches      |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_nftables_rule` |
| Collection Mode | Metadata |
| Required Capabilities | `nft_access` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | Yes |
| Batch Collection | No |

---

## Channel Integration

Runs `nft list ruleset` over the configured scan channel.
Reads the **target** host's loaded ruleset. **Privileged:** `nft` requires
root (`Operation not permitted` otherwise) — a non-root scan returns
`found = false`. Run with a root-capable credential (or sudo-wrapped execution).

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `nft list ruleset`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


```bash
nft list ruleset
# table inet filter {
#   chain input { type filter hook input priority filter; policy drop; ... }
# }
```

Whitelisted: `nft` (`/usr/sbin/nft`).

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### A nftables table exists (CIS 4.3.4)

```esp
OBJECT target
    match `table `
OBJECT_END

STATE present
    found boolean = true
STATE_END

CTN linux_nftables_rule
    TEST all all AND
    STATE_REF present
    OBJECT_REF target
CTN_END
```

### Input base chain default-deny (CIS 4.3.8)

```esp
OBJECT target
    match `hook input`
OBJECT_END

STATE drop_policy
    found boolean = true
    line string contains `policy drop`
STATE_END

CTN linux_nftables_rule
    TEST all all AND
    STATE_REF drop_policy
    OBJECT_REF target
CTN_END
```

---

## CIS Coverage

| Benchmark        | Section | Notes |
| ---------------- | ------- | ----- |
| CIS Ubuntu 24.04 | §4.3.x  | table exists, base chains, loopback, default deny. (nftables *installed* → `linux_dpkg_package`; *service enabled* → `systemd_service`.) |

---

## Error Conditions

| Condition          | Error Type         | Effect on TEST  |
| ------------------ | ------------------ | --------------- |
| `nft` not found    | `CollectionFailed` | Error state     |
| not root / no rules | N/A               | `found` = false |

---

## Related CTN Types

| CTN Type             | Relationship                          |
| -------------------- | ------------------------------------- |
| `linux_ufw_rule`     | ufw front-end (mutually exclusive use) |
| `linux_dpkg_package` | nftables package installed            |
| `firewalld_rule`     | Rocky/RHEL host-firewall equivalent   |
