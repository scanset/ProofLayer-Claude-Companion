# aws_secretsmanager_secret_scoped

## Overview

Scoped-injection variant of [`aws_secretsmanager_secret`](aws_secretsmanager_secret.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::SecretsManager::Secret` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_secretsmanager_secret_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `secret_id` | `metadata.secret_id` | **Yes** |
| `region` | `metadata.region` | No |

`target_asset_type`: `AWS::SecretsManager::Secret`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET secrets union
    OBJECT t
        target `AWS::SecretsManager::Secret`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field       | Type   | Required | Description                                | Example                          |
| ----------- | ------ | -------- | ------------------------------------------ | -------------------------------- |
| `secret_id` | string | **Yes**  | Secret name or ARN                         | `prooflayer-demo/db/credentials` |
| `region`    | string | No       | AWS region override (passed as `--region`) | `us-east-1`                      |

---

## Commands Executed

### Command 1: describe-secret

**Resulting command:**

```
aws secretsmanager describe-secret --secret-id prooflayer-demo/db/credentials --output json
```

**Sample response:**

```json
{
  "ARN": "arn:aws:secretsmanager:us-east-1:486027077516:secret:prooflayer-demo/db/credentials-Sp6FkL",
  "Name": "prooflayer-demo/db/credentials",
  "Description": "ProofLayer PostgreSQL credentials",
  "KmsKeyId": "arn:aws:kms:us-east-1:486027077516:key/3c418345-78b1-4687-ac90-399246730cae",
  "LastChangedDate": "2026-03-23T22:16:21.656000+00:00",
  "LastAccessedDate": "2026-03-25T00:00:00+00:00",
  "Tags": [
    { "Key": "SecretType", "Value": "database" },
    { "Key": "ManagedBy", "Value": "terraform" }
  ],
  "VersionIdsToStages": {
    "terraform-20260323221621262500000001": ["AWSCURRENT"],
    "terraform-20260323220857340500000007": ["AWSPREVIOUS"]
  }
}
```

**Response parsing:**

| Collected Field       | Source                                                          | Notes                                |
| --------------------- | --------------------------------------------------------------- | ------------------------------------ |
| `secret_name`         | `Name`                                                          |                                      |
| `secret_arn`          | `ARN`                                                           |                                      |
| `kms_key_id`          | `KmsKeyId`                                                      | Absent if using AWS managed key      |
| `description`         | `Description`                                                   |                                      |
| `rotation_enabled`    | `RotationEnabled` (absent = false)                              | Derived — defaults false when absent |
| `has_current_version` | Derived: any `VersionIdsToStages` value contains `"AWSCURRENT"` | Confirms secret has active version   |
| `tag_key:<Key>`       | `Tags[*]` flat map                                              | One scalar per tag                   |

---

### Error Detection

| Stderr contains             | Outcome            |
| --------------------------- | ------------------ |
| `ResourceNotFoundException` | `found=false`      |
| `SecretNotFound`            | `found=false`      |
| `AccessDenied`              | Collection failed |
| Anything else               | Collection failed |

---

## Collected Data Fields

### Scalar Fields

| Field                 | Type    | Always Present | Source                             |
| --------------------- | ------- | -------------- | ---------------------------------- |
| `found`               | boolean | Yes            | Derived — `true` if secret exists  |
| `secret_name`         | string  | When found     | `Name`                             |
| `secret_arn`          | string  | When found     | `ARN`                              |
| `kms_key_id`          | string  | When encrypted | `KmsKeyId`                         |
| `description`         | string  | When found     | `Description`                      |
| `rotation_enabled`    | boolean | When found     | `RotationEnabled` (absent = false) |
| `has_current_version` | boolean | When found     | Derived from `VersionIdsToStages`  |
| `tag_key:<Key>`       | string  | When found     | One field per tag                  |

### RecordData Field

| Field      | Type       | Always Present | Description                                                |
| ---------- | ---------- | -------------- | ---------------------------------------------------------- |
| `resource` | RecordData | Yes            | Full `describe-secret` response. Empty `{}` when not found |

---

## RecordData Structure

| Path                                | Type   | Example Value                                                                                  |
| ----------------------------------- | ------ | ---------------------------------------------------------------------------------------------- |
| `Name`                              | string | `"prooflayer-demo/db/credentials"`                                                             |
| `ARN`                               | string | `"arn:aws:secretsmanager:us-east-1:486027077516:secret:prooflayer-demo/db/credentials-Sp6FkL"` |
| `KmsKeyId`                          | string | `"arn:aws:kms:us-east-1:486027077516:key/3c418345-..."`                                        |
| `Description`                       | string | `"ProofLayer PostgreSQL credentials"`                                                          |
| `VersionIdsToStages.<version-id>.0` | string | `"AWSCURRENT"`                                                                                 |
| `Tags.0.Key`                        | string | `"SecretType"`                                                                                 |
| `Tags.0.Value`                      | string | `"database"`                                                                                   |

---

## State Fields

| State Field           | Type       | Allowed Operations              | Maps To Collected Field   |
| --------------------- | ---------- | ------------------------------- | ------------------------- |
| `found`               | boolean    | `=`, `!=`                       | `found`                   |
| `secret_name`         | string     | `=`, `!=`, `contains`, `starts` | `secret_name`             |
| `secret_arn`          | string     | `=`, `!=`, `contains`, `starts` | `secret_arn`              |
| `kms_key_id`          | string     | `=`, `!=`, `contains`, `starts` | `kms_key_id`              |
| `description`         | string     | `=`, `!=`, `contains`           | `description`             |
| `rotation_enabled`    | boolean    | `=`, `!=`                       | `rotation_enabled`        |
| `has_current_version` | boolean    | `=`, `!=`                       | `has_current_version`     |
| `tag_key:<Key>`       | string     | `=`, `!=`, `contains`           | `tag_key:<Key>` (dynamic) |
| `record`              | RecordData | (record checks)                 | `resource`                |

---

## Collection Strategy

| Property                     | Value                                 |
| ---------------------------- | ------------------------------------- |
| CTN Type               | `aws_secretsmanager_secret`           |
| Collection Mode              | Metadata                              |
| Required Capabilities        | `aws_cli`, `secretsmanager_read`      |
| Expected Collection Time     | ~1500ms                               |
| Memory Usage                 | ~2MB                                  |
| Network Intensive            | Yes                                   |
| CPU Intensive                | No                                    |
| Requires Elevated Privileges | No                                    |
| Batch Collection             | No                                    |

### Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": ["secretsmanager:DescribeSecret"],
  "Resource": "*"
}
```

---

## ESP Examples

### Secret encrypted with CMK and has active version (KSI-SVC-ASM, KSI-AFR-UCM)

```esp
OBJECT db_secret
    secret_id `prooflayer-demo/db/credentials`
    region `us-east-1`
OBJECT_END

STATE secret_compliant
    found boolean = true
    kms_key_id string starts `arn:aws:kms:`
    has_current_version boolean = true
STATE_END

CTN aws_secretsmanager_secret
    TEST all all AND
    STATE_REF secret_compliant
    OBJECT_REF db_secret
CTN_END
```

### Validate secret tag for type classification

```esp
STATE secret_tagged
    found boolean = true
    tag_key:SecretType string = `database`
    tag_key:ManagedBy string = `terraform`
STATE_END
```

---

## Error Conditions

| Condition                       | Error Type                   | Outcome       |
| ------------------------------- | ---------------------------- | ------------- |
| Secret not found                | N/A (not an error)           | `found=false` |
| `secret_id` missing from object | Invalid object configuration | Error         |
| IAM access denied               | Collection failed           | Error         |
| Incompatible CTN type           | CTN type mismatch      | Error         |

---

## Related CTN Types

| CTN Type           | Relationship                                                         |
| ------------------ | -------------------------------------------------------------------- |
| `aws_kms_key`      | KMS key used to encrypt the secret                                   |
| `aws_vpc_endpoint` | Secrets Manager VPC endpoint keeps secret access private             |
| `aws_iam_role`     | EC2 role granted `secretsmanager:GetSecretValue` to retrieve secrets |

---

## Scoped ESP Policy Example

```esp
DEF
    SET db_creds union
        OBJECT t
            target `AWS::SecretsManager::Secret`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE db_creds_check
        found boolean = true
        kms_key_id string contains `KMS_KEY_ID`
    STATE_END

    CRI AND
        CTN aws_secretsmanager_secret_scoped
            TEST all all AND
            STATE_REF db_creds_check
            SET_REF db_creds
        CTN_END
    CRI_END
DEF_END
```

