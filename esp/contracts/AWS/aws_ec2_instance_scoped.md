# aws_ec2_instance_scoped

## Overview

Scoped-injection variant of [`aws_ec2_instance`](aws_ec2_instance.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::EC2::Instance` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_ec2_instance_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `instance_id` | `metadata.instance_id` | **Yes** |
| `region` | `metadata.region` | No |

`target_asset_type`: `AWS::EC2::Instance`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET instances union
    OBJECT t
        target `AWS::EC2::Instance`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field         | Type   | Required | Description                                | Example               |
| ------------- | ------ | -------- | ------------------------------------------ | --------------------- |
| `instance_id` | string | **Yes**  | EC2 instance ID (exact match)              | `i-02dc10f9292c0a933` |
| `region`      | string | No       | AWS region override (passed as `--region`) | `us-east-1`           |

---

## Commands Executed

### Command 1: describe-instances

**Resulting command:**

```
aws ec2 describe-instances --instance-ids i-02dc10f9292c0a933 --output json
```

**Response shape:** `Reservations[0].Instances[0]`

**Sample response (abbreviated):**

```json
{
  "Reservations": [
    {
      "Instances": [
        {
          "InstanceId": "i-02dc10f9292c0a933",
          "InstanceType": "t3.large",
          "ImageId": "ami-078448b73f6313465",
          "State": { "Code": 16, "Name": "running" },
          "MetadataOptions": {
            "HttpTokens": "required",
            "HttpPutResponseHopLimit": 1,
            "HttpEndpoint": "enabled"
          },
          "PublicDnsName": "",
          "IamInstanceProfile": {
            "Arn": "arn:aws:iam::486027077516:instance-profile/prooflayer-demo-ec2-profile"
          },
          "SecurityGroups": [
            {
              "GroupId": "sg-0ee1fed6cac898cc7",
              "GroupName": "prooflayer-demo-vm-sg"
            }
          ],
          "Monitoring": { "State": "disabled" },
          "CurrentInstanceBootMode": "uefi",
          "EbsOptimized": false,
          "VpcId": "vpc-0ea38d2598962fda8",
          "SubnetId": "subnet-0765f76c6a2dda34e",
          "RootDeviceName": "/dev/sda1",
          "BlockDeviceMappings": [
            {
              "DeviceName": "/dev/sda1",
              "Ebs": {
                "VolumeId": "vol-0a53ae7e9518978de",
                "Status": "attached"
              }
            }
          ],
          "Tags": [{ "Key": "Name", "Value": "prooflayer-demo-vm" }]
        }
      ]
    }
  ]
}
```

**Response parsing:**

| Collected Field            | JSON Path                                           | Notes                                        |
| -------------------------- | --------------------------------------------------- | -------------------------------------------- |
| `instance_id`              | `InstanceId`                                        |                                              |
| `instance_type`            | `InstanceType`                                      |                                              |
| `image_id`                 | `ImageId`                                           |                                              |
| `state`                    | `State.Name`                                        | `running`, `stopped`, `terminated`, etc.     |
| `imdsv2_required`          | Derived: `MetadataOptions.HttpTokens == "required"` | `true` when HttpTokens is `required`         |
| `metadata_hop_limit`       | `MetadataOptions.HttpPutResponseHopLimit`           | Should be `1` to prevent SSRF token theft    |
| `has_public_ip`            | Derived: `PublicIpAddress` present and non-empty    | `false` when field is absent or empty string |
| `iam_instance_profile_arn` | `IamInstanceProfile.Arn`                            |                                              |
| `security_group_id`        | `SecurityGroups[0].GroupId`                         | First SG only                                |
| `monitoring_state`         | `Monitoring.State`                                  | `disabled` or `enabled`                      |
| `boot_mode`                | `CurrentInstanceBootMode`                           | `uefi` or `legacy-bios`                      |
| `ebs_optimized`            | `EbsOptimized`                                      |                                              |
| `vpc_id`                   | `VpcId`                                             |                                              |
| `subnet_id`                | `SubnetId`                                          |                                              |
| `tag_key:<Key>`            | `Tags[*]` flat map                                  | One scalar per tag                           |

---

### Command 2: describe-volumes (root volume encryption lookup)

`describe-instances` does not return EBS encryption status. The collector extracts the root volume ID from `BlockDeviceMappings` where `DeviceName == RootDeviceName`, then makes a second call.

**Resulting command:**

```
aws ec2 describe-volumes --volume-ids vol-0a53ae7e9518978de --output json
```

**Response parsing:**

- `Volumes[0].Encrypted` → `root_volume_encrypted` scalar (boolean)

This call is **non-fatal** — if it fails, `root_volume_encrypted` defaults to `false` rather than failing collection.

---

### Error Detection

| Stderr contains               | Outcome            |
| ----------------------------- | ------------------ |
| `InvalidInstanceID.NotFound`  | `found=false`      |
| `InvalidInstanceID.Malformed` | `found=false`      |
| `AccessDenied`                | Collection failed |
| Anything else                 | Collection failed |

---

## Collected Data Fields

### Scalar Fields

| Field                      | Type    | Always Present | Source                                              |
| -------------------------- | ------- | -------------- | --------------------------------------------------- |
| `found`                    | boolean | Yes            | Derived — `true` if instance exists                 |
| `instance_id`              | string  | When found     | `InstanceId`                                        |
| `instance_type`            | string  | When found     | `InstanceType`                                      |
| `image_id`                 | string  | When found     | `ImageId`                                           |
| `state`                    | string  | When found     | `State.Name`                                        |
| `imdsv2_required`          | boolean | When found     | Derived: `MetadataOptions.HttpTokens == "required"` |
| `metadata_hop_limit`       | integer | When found     | `MetadataOptions.HttpPutResponseHopLimit`           |
| `has_public_ip`            | boolean | When found     | Derived: `PublicIpAddress` present and non-empty    |
| `root_volume_encrypted`    | boolean | When found     | From second describe-volumes call on root volume    |
| `vpc_id`                   | string  | When found     | `VpcId`                                             |
| `subnet_id`                | string  | When found     | `SubnetId`                                          |
| `iam_instance_profile_arn` | string  | When found     | `IamInstanceProfile.Arn`                            |
| `security_group_id`        | string  | When found     | `SecurityGroups[0].GroupId`                         |
| `monitoring_state`         | string  | When found     | `Monitoring.State`                                  |
| `boot_mode`                | string  | When found     | `CurrentInstanceBootMode`                           |
| `ebs_optimized`            | boolean | When found     | `EbsOptimized`                                      |
| `tag_key:<Key>`            | string  | When found     | One field per tag from `Tags` array                 |

### RecordData Field

| Field      | Type       | Always Present | Description                                           |
| ---------- | ---------- | -------------- | ----------------------------------------------------- |
| `resource` | RecordData | Yes            | Full `Instances[0]` object. Empty `{}` when not found |

---

## RecordData Structure

Key paths available for record checks:

| Path                                      | Type    | Example Value                 |
| ----------------------------------------- | ------- | ----------------------------- |
| `MetadataOptions.HttpTokens`              | string  | `"required"`                  |
| `MetadataOptions.HttpPutResponseHopLimit` | integer | `1`                           |
| `MetadataOptions.HttpEndpoint`            | string  | `"enabled"`                   |
| `State.Name`                              | string  | `"running"`                   |
| `IamInstanceProfile.Arn`                  | string  | `"arn:aws:iam::..."`          |
| `SecurityGroups.0.GroupId`                | string  | `"sg-0ee1fed6cac898cc7"`      |
| `Monitoring.State`                        | string  | `"disabled"`                  |
| `CurrentInstanceBootMode`                 | string  | `"uefi"`                      |
| `BlockDeviceMappings.0.DeviceName`        | string  | `"/dev/sda1"`                 |
| `BlockDeviceMappings.0.Ebs.VolumeId`      | string  | `"vol-0a53ae7e9518978de"`     |
| `BlockDeviceMappings.0.Ebs.Status`        | string  | `"attached"`                  |
| `Tags.*.Key`                              | string  | (all tag keys via wildcard)   |
| `Tags.*.Value`                            | string  | (all tag values via wildcard) |

---

## State Fields

| State Field                | Type       | Allowed Operations              | Maps To Collected Field    |
| -------------------------- | ---------- | ------------------------------- | -------------------------- |
| `found`                    | boolean    | `=`, `!=`                       | `found`                    |
| `instance_id`              | string     | `=`, `!=`                       | `instance_id`              |
| `instance_type`            | string     | `=`, `!=`                       | `instance_type`            |
| `image_id`                 | string     | `=`, `!=`                       | `image_id`                 |
| `state`                    | string     | `=`, `!=`                       | `state`                    |
| `imdsv2_required`          | boolean    | `=`, `!=`                       | `imdsv2_required`          |
| `metadata_hop_limit`       | int        | `=`, `!=`, `>=`, `<=`, `>`, `<` | `metadata_hop_limit`       |
| `has_public_ip`            | boolean    | `=`, `!=`                       | `has_public_ip`            |
| `root_volume_encrypted`    | boolean    | `=`, `!=`                       | `root_volume_encrypted`    |
| `vpc_id`                   | string     | `=`, `!=`                       | `vpc_id`                   |
| `subnet_id`                | string     | `=`, `!=`                       | `subnet_id`                |
| `iam_instance_profile_arn` | string     | `=`, `!=`, `contains`, `starts` | `iam_instance_profile_arn` |
| `security_group_id`        | string     | `=`, `!=`                       | `security_group_id`        |
| `monitoring_state`         | string     | `=`, `!=`                       | `monitoring_state`         |
| `boot_mode`                | string     | `=`, `!=`                       | `boot_mode`                |
| `ebs_optimized`            | boolean    | `=`, `!=`                       | `ebs_optimized`            |
| `tag_key:<Key>`            | string     | `=`, `!=`, `contains`           | `tag_key:<Key>` (dynamic)  |
| `record`                   | RecordData | (record checks)                 | `resource`                 |

---

## Collection Strategy

| Property                     | Value                        |
| ---------------------------- | ---------------------------- |
| CTN Type               | `aws_ec2_instance`           |
| Collection Mode              | Content                      |
| Required Capabilities        | `aws_cli`, `ec2_read`        |
| Expected Collection Time     | ~2000ms (two API calls)      |
| Memory Usage                 | ~5MB                         |
| Network Intensive            | Yes                          |
| CPU Intensive                | No                           |
| Requires Elevated Privileges | No                           |
| Batch Collection             | No                           |

### Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": ["ec2:DescribeInstances", "ec2:DescribeVolumes"],
  "Resource": "*"
}
```

---

## ESP Examples

### IMDSv2 enforced, no public IP, root volume encrypted (KSI-CNA-MAT, KSI-SVC-VRI)

```esp
OBJECT prooflayer_vm
    instance_id `i-02dc10f9292c0a933`
    region `us-east-1`
OBJECT_END

STATE instance_hardened
    found boolean = true
    state string = `running`
    imdsv2_required boolean = true
    metadata_hop_limit int = 1
    has_public_ip boolean = false
    root_volume_encrypted boolean = true
STATE_END

CTN aws_ec2_instance
    TEST all all AND
    STATE_REF instance_hardened
    OBJECT_REF prooflayer_vm
CTN_END
```

### Record checks for metadata options

```esp
STATE imds_details
    found boolean = true
    record
        field MetadataOptions.HttpTokens string = `required`
        field MetadataOptions.HttpPutResponseHopLimit int = 1
        field MetadataOptions.HttpEndpoint string = `enabled`
    record_end
STATE_END
```

---

## Error Conditions

| Condition                          | Error Type                   | Outcome                       |
| ---------------------------------- | ---------------------------- | ----------------------------- |
| Instance not found                 | N/A (not an error)           | `found=false`                 |
| `instance_id` missing from object  | Invalid object configuration | Error                         |
| IAM access denied                  | Collection failed           | Error                         |
| Root volume describe-volumes fails | Non-fatal                    | `root_volume_encrypted=false` |
| Incompatible CTN type              | CTN type mismatch      | Error                         |

---

## Related CTN Types

| CTN Type             | Relationship                                                  |
| -------------------- | ------------------------------------------------------------- |
| `aws_ebs_volume`     | Validates data volume encryption independently of root volume |
| `aws_security_group` | Security group attached to the instance                       |
| `aws_vpc`            | VPC the instance resides in                                   |
| `aws_iam_role`       | IAM role backing the instance profile                         |

# aws_ec2_instance

---

## Scoped ESP Policy Example

```esp
DEF
    SET instances union
        OBJECT t
            target `AWS::EC2::Instance`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE st_instance_hardened
        found boolean = true
        imdsv2_required boolean = true
        root_volume_encrypted boolean = true
    STATE_END

    CRI AND
        CTN aws_ec2_instance_scoped
            TEST all all AND
            STATE_REF st_instance_hardened
            SET_REF instances
        CTN_END
    CRI_END
DEF_END
```

