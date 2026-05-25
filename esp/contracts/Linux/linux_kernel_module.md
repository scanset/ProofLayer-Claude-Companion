# linux_kernel_module

## Overview

Validates whether a Linux kernel module is **loadable** and/or **currently
loaded**, using `modprobe -n -v <module>` (a dry run that never loads anything)
and `lsmod`. Backs the CIS family *"Ensure `<X>` kernel module is not
available"* (cramfs, freevxfs, hfs, hfsplus, squashfs, udf, usb-storage, …),
which require both that the module cannot be loaded and that it is not present
in the running kernel.

**Platform:** Linux (distro-agnostic — identical on Rocky/RHEL and Ubuntu)
**Collection Method:** `modprobe -n -v` (dry run) + `lsmod` run on the target host
**Use Case:** Attack-surface reduction via unneeded-filesystem / unneeded-driver
module disablement.

---

## Object Fields (Input)

| Field         | Type   | Required | Description       | Example                       |
| ------------- | ------ | -------- | ----------------- | ----------------------------- |
| `module_name` | string | Yes      | Kernel module name | `cramfs`, `usb-storage`, `udf` |

### Notes

- `-` and `_` are interchangeable in module names; the collector normalizes both
  sides when matching `lsmod`.

---

## Collected Data Fields (Output)

| Field        | Type    | Required | Description                                                       |
| ------------ | ------- | -------- | ----------------------------------------------------------------- |
| `found`      | boolean | Yes      | Whether the module is known/available to this kernel              |
| `loadable`   | boolean | No       | Whether the module would actually load (dry run shows `insmod`)   |
| `loaded`     | boolean | No       | Whether the module is present in the running kernel (`lsmod`)     |
| `resolution` | string  | No       | Raw `modprobe -n -v` resolution line (evidence)                   |

**Notes:**

- When `modprobe` cannot resolve the module (not available / pre-compiled),
  the collector returns `found = false`, `loadable = false`, `loaded = false`
  — the CIS-compliant default state.
- `loadable` is `false` when the module is neutralized via
  `install /bin/true` or `install /bin/false`.

---

## State Fields (Validation)

| Field        | Type    | Operations            | Maps To      | Description                          |
| ------------ | ------- | --------------------- | ------------ | ------------------------------------ |
| `found`      | boolean | `=`, `!=`             | `found`      | Module known to the system           |
| `loadable`   | boolean | `=`, `!=`             | `loadable`   | Module would load on demand          |
| `loaded`     | boolean | `=`, `!=`             | `loaded`     | Module currently in running kernel   |
| `resolution` | string  | `=`, `!=`, `contains` | `resolution` | Raw modprobe resolution line         |

---

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type       | `linux_kernel_module` |
| Collection Mode | Metadata |
| Required Capabilities | `modprobe_access` |
| Expected Collection Time | ~50ms |
| Memory Usage | ~1MB |
| Network Intensive | No |
| CPU Intensive | No |
| Requires Elevated Privileges | No |
| Batch Collection | No |

---

## Channel Integration

Shells out over the configured scan channel. A
`--channel ssh|aws-ssm|az-bastion` scan therefore inspects the **target**
host's kernel, not the scanner's.

---

## Command Execution

**Recorded command (CollectionMethod / reproducibility):** `modprobe -n -v <module> ; lsmod`

This exact string is stamped into the scan's `CollectionMethod` and persisted in the AssessorPackage evidence, so an auditor can reproduce the check by hand. It is sourced verbatim from the collector.


### Commands

```bash
modprobe -n -v <module>   # dry run — resolves load action, loads nothing
lsmod                     # running module table (/proc/modules)
```

### Output Format

`modprobe -n -v` prints the action it *would* take:

```
install /bin/true        # neutralized -> not loadable
insmod /lib/modules/.../cramfs.ko   # would load -> loadable
modprobe: FATAL: Module cramfs not found ...   # unavailable -> found=false
```

### Whitelisted Commands

| Command               | Path        | Description           |
| --------------------- | ----------- | --------------------- |
| `modprobe`            | PATH lookup | Module resolution     |
| `/usr/sbin/modprobe`  | Absolute    | Common location       |
| `/sbin/modprobe`      | Absolute    | Alternative location  |
| `lsmod`               | PATH lookup | Running module table  |
| `/usr/sbin/lsmod`     | Absolute    | Common location       |
| `/sbin/lsmod`         | Absolute    | Alternative location  |

---

## ESP Examples

**IMPORTANT:** OBJECT fields use `field_name `value`` (no type keyword). STATE fields use `field_name type operator `value`` (type keyword required). The CTN type goes on the CTN block line, NOT on the OBJECT declaration.

### Ensure the cramfs module is not available (CIS 1.1.1.1)

```esp
OBJECT cramfs
    module_name `cramfs`
OBJECT_END

STATE not_available
    loadable boolean = false
    loaded boolean = false
STATE_END

CTN linux_kernel_module
    TEST at_least_one all AND
    STATE_REF not_available
    OBJECT_REF cramfs
CTN_END
```

### Ensure usb-storage is neutralized via install directive

```esp
OBJECT usb_storage
    module_name `usb-storage`
OBJECT_END

STATE neutralized
    loadable boolean = false
    resolution string contains `/bin/true`
STATE_END

CTN linux_kernel_module
    TEST at_least_one all AND
    STATE_REF neutralized
    OBJECT_REF usb_storage
CTN_END
```

---

## CIS Coverage

Distro-agnostic. Backs the *"kernel module is not available"* recommendations:

| Benchmark           | Section   | Examples                                            |
| ------------------- | --------- | --------------------------------------------------- |
| CIS Rocky Linux 9   | 1.1.1.x   | cramfs, freevxfs, hfs, hfsplus, squashfs, udf, usb-storage |
| CIS Ubuntu 24.04    | 1.1.1.x   | cramfs, freevxfs, hfs, hfsplus, jffs2, udf, usb-storage |

---

## Error Conditions

| Condition                       | Error Type         | Effect on TEST          |
| ------------------------------- | ------------------ | ----------------------- |
| `modprobe` binary not found     | `CollectionFailed` | Error state             |
| `modprobe`/channel timeout (>5s) | `CollectionFailed` | Error state             |
| Module not available            | N/A                | `found` = false, `loadable` = false |
| `lsmod` fails                   | N/A                | `loaded` = false (modprobe evidence retained) |

---

## Security Considerations

- `modprobe -n -v` is a **dry run**: it resolves the load action but never
  inserts the module. `lsmod` is a pure read of `/proc/modules`. Read-only,
  no side effects.
- Reading `/proc/modules` does not require elevated privileges; `modprobe`
  resolution is also unprivileged.

---

## Related CTN Types

| CTN Type       | Relationship                                                       |
| -------------- | ------------------------------------------------------------------ |
| `file_content` | Validate `install`/`blacklist` directives in `/etc/modprobe.d/*.conf` for persistence |
| `sysctl_parameter` | Many disabled-feature controls pair a module check with a sysctl |
