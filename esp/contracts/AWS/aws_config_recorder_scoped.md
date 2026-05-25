# aws_config_recorder_scoped

## Overview

Scoped-injection variant of [`aws_config_recorder`](aws_config_recorder.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::Config::ConfigurationRecorder` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_config_recorder_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `recorder_name` | `metadata.recorder_name` | **Yes** |
| `region` | `metadata.region` | No |

`target_asset_type`: `AWS::Config::ConfigurationRecorder`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET configurationrecorders union
    OBJECT t
        target `AWS::Config::ConfigurationRecorder`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field           | Type   | Required | Description                                | Example                           |
| --------------- | ------ | -------- | ------------------------------------------ | --------------------------------- |
| `recorder_name` | string | **Yes**  | Config recorder name (exact match)         | `prooflayer-demo-config-recorder` |
| `region`        | string | No       | AWS region override (passed as `--region`) | `us-east-1`                       |

---

## Commands Executed

### Command 1: describe-configuration-recorders

```
aws configservice describe-configuration-recorders --configuration-recorder-names prooflayer-demo-config-recorder --output json
```

**Sample response (abbreviated):**

```json
{
  "ConfigurationRecorders": [
    {
      "name": "prooflayer-demo-config-recorder",
      "roleARN": "arn:aws:iam::486027077516:role/prooflayer-demo-config-role",
      "recordingGroup": {
        "allSupported": true,
        "includeGlobalResourceTypes": true
      },
      "recordingMode": {
        "recordingFrequency": "CONTINUOUS"
      }
    }
  ]
}
```

### Command 2: describe-configuration-recorder-status

```
aws configservice describe-configuration-recorder-status --configuration-recorder-names prooflayer-demo-config-recorder --output json
```

**Sample response:**

```json
{
  "ConfigurationRecordersStatus": [
    {
      "name": "prooflayer-demo-config-recorder",
      "lastStartTime": "2026-03-24T16:24:59.146000+00:00",
      "recording": true,
      "lastStatus": "SUCCESS",
      "lastStatusChangeTime": "2026-03-26T15:16:10.098000+00:00"
    }
  ]
}
```

---

## Collected Data Fields

### Scalar Fields

| Field                           | Type    | Always Present | Source                                      |
| ------------------------------- | ------- | -------------- | ------------------------------------------- |
| `found`                         | boolean | Yes            | Derived — `true` if recorder found          |
| `recorder_name`                 | string  | When found     | `name`                                      |
| `all_supported`                 | boolean | When found     | `recordingGroup.allSupported`               |
| `include_global_resource_types` | boolean | When found     | `recordingGroup.includeGlobalResourceTypes` |
| `recording_frequency`           | string  | When found     | `recordingMode.recordingFrequency`          |
| `recording`                     | boolean | When found     | `Status.recording`                          |
| `last_status`                   | string  | When found     | `Status.lastStatus`                         |

### RecordData Field

| Field      | Type       | Always Present | Description                                                |
| ---------- | ---------- | -------------- | ---------------------------------------------------------- |
| `resource` | RecordData | Yes            | Merged recorder config + status. Empty `{}` when not found |

---

## RecordData Structure

```
Recorder.name                                    → "prooflayer-demo-config-recorder"
Recorder.roleARN                                 → "arn:aws:iam::486027077516:role/..."
Recorder.recordingGroup.allSupported             → true
Recorder.recordingGroup.includeGlobalResourceTypes → true
Recorder.recordingMode.recordingFrequency        → "CONTINUOUS"
Status.recording                                 → true
Status.lastStatus                                → "SUCCESS"
Status.lastStartTime                             → "2026-03-24T16:24:59.146000+00:00"
```

---

## State Fields

| State Field                     | Type       | Allowed Operations | Maps To Collected Field         |
| ------------------------------- | ---------- | ------------------ | ------------------------------- |
| `found`                         | boolean    | `=`, `!=`          | `found`                         |
| `recorder_name`                 | string     | `=`, `!=`          | `recorder_name`                 |
| `all_supported`                 | boolean    | `=`, `!=`          | `all_supported`                 |
| `include_global_resource_types` | boolean    | `=`, `!=`          | `include_global_resource_types` |
| `recording_frequency`           | string     | `=`, `!=`          | `recording_frequency`           |
| `recording`                     | boolean    | `=`, `!=`          | `recording`                     |
| `last_status`                   | string     | `=`, `!=`          | `last_status`                   |
| `record`                        | RecordData | (record checks)    | `resource`                      |

---

## Collection Strategy

| Property                 | Value                           |
| ------------------------ | ------------------------------- |
| CTN Type           | `aws_config_recorder`           |
| Collection Mode          | Content                         |
| Required Capabilities    | `aws_cli`, `config_read`        |
| Expected Collection Time | ~2000ms (two API calls)         |
| Memory Usage             | ~2MB                            |
| Batch Collection         | No                              |

### Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": [
    "config:DescribeConfigurationRecorders",
    "config:DescribeConfigurationRecorderStatus"
  ],
  "Resource": "*"
}
```

---

## ESP Examples

### Config recorder active and recording all resources (KSI-MLA-LET, KSI-CMT-VTD)

```esp
OBJECT config_recorder
    recorder_name `prooflayer-demo-config-recorder`
    region `us-east-1`
OBJECT_END

STATE recorder_compliant
    found boolean = true
    recording boolean = true
    all_supported boolean = true
    include_global_resource_types boolean = true
    recording_frequency string = `CONTINUOUS`
    last_status string = `SUCCESS`
STATE_END

CTN aws_config_recorder
    TEST all all AND
    STATE_REF recorder_compliant
    OBJECT_REF config_recorder
CTN_END
```

---

## Error Conditions

| Condition                              | Error Type                   | Outcome       |
| -------------------------------------- | ---------------------------- | ------------- |
| Recorder not found                     | N/A (not an error)           | `found=false` |
| `recorder_name` missing from object    | Invalid object configuration | Error         |
| IAM access denied                      | Collection failed           | Error         |
| Status call fails after recorder found | Collection failed           | Error         |
| Incompatible CTN type                  | CTN type mismatch      | Error         |

---

## Related CTN Types

| CTN Type          | Relationship                                             |
| ----------------- | -------------------------------------------------------- |
| `aws_config_rule` | Config rules depend on the recorder being active         |
| `aws_iam_role`    | Config recorder assumes an IAM role to deliver snapshots |
| `aws_s3_bucket`   | Config snapshots are delivered to an S3 bucket           |

---

## Scoped ESP Policy Example

```esp
DEF
    SET config_recorder_set union
        OBJECT t
            target `AWS::Config::ConfigurationRecorder`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE config_recorder_check
        found boolean = true
        recording boolean = true
        all_supported boolean = true
        include_global_resource_types boolean = true
    STATE_END

    CRI AND
        CTN aws_config_recorder_scoped
            TEST all all AND
            STATE_REF config_recorder_check
            SET_REF config_recorder_set
        CTN_END
    CRI_END
DEF_END
```

