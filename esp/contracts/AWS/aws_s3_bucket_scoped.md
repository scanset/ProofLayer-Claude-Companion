# aws_s3_bucket_scoped

## Overview

Scoped-injection variant of [`aws_s3_bucket`](aws_s3_bucket.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::S3::Bucket` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_s3_bucket_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `bucket_name` | `metadata.bucket_name` | **Yes** |

`target_asset_type`: `AWS::S3::Bucket`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET buckets union
    OBJECT t
        target `AWS::S3::Bucket`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field         | Type   | Required | Description                                | Example                             |
| ------------- | ------ | -------- | ------------------------------------------ | ----------------------------------- |
| `bucket_name` | string | **Yes**  | S3 bucket name (exact match)               | `prooflayer-demo-security-findings` |
| `region`      | string | No       | AWS region override (passed as `--region`) | `us-east-1`                         |

- `bucket_name` is **required**. If missing, the collector returns Invalid object configuration.
- If `region` is omitted, the AWS CLI's default region resolution applies (env vars, config file, instance metadata).
- `LocationConstraint` is `null` in API responses for `us-east-1` buckets. The collector normalizes this to the string `"us-east-1"`.

---

## Commands Executed

All commands are issued to the `aws` CLI binary with arguments appended in this order:

```
aws <service> <operation> [--region <region>] --output json [additional args...]
```

### Command 1: get-bucket-encryption

**Resulting command:**

```
aws s3api get-bucket-encryption --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "ServerSideEncryptionConfiguration": {
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "arn:aws:kms:us-east-1:486027077516:key/3c418345-78b1-4687-ac90-399246730cae"
        },
        "BucketKeyEnabled": true
      }
    ]
  }
}
```

**Response parsing:** Extract `Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm`, `Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID`, and `Rules[0].BucketKeyEnabled`. If the bucket has no encryption configured, the API returns a `ServerSideEncryptionConfigurationNotFoundError` — the collector treats this as missing fields (not a collection error).

---

### Command 2: get-bucket-versioning

**Resulting command:**

```
aws s3api get-bucket-versioning --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "Status": "Enabled"
}
```

**Response parsing:** Extract `Status` as a string. If versioning has never been enabled, the response is an empty object `{}` and the field is absent from collected data.

---

### Command 3: get-public-access-block

**Resulting command:**

```
aws s3api get-public-access-block --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "PublicAccessBlockConfiguration": {
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }
}
```

**Response parsing:** Extract all four booleans from `PublicAccessBlockConfiguration`. If the public access block is not configured, the API returns `NoSuchPublicAccessBlockConfiguration` — the collector treats this as missing fields.

---

### Command 4: get-bucket-lifecycle-configuration

**Resulting command:**

```
aws s3api get-bucket-lifecycle-configuration --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K",
  "Rules": [
    {
      "Expiration": {
        "Days": 2555
      },
      "ID": "findings-retention",
      "Filter": {
        "Prefix": ""
      },
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 365,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 90,
          "StorageClass": "STANDARD_IA"
        }
      ]
    }
  ]
}
```

**Response parsing:** Extract `Rules` as a JSON array. The scalar field `lifecycle_enabled` is derived as `true` if any rule with `Status == "Enabled"` exists. If no lifecycle configuration exists, the API returns `NoSuchLifecycleConfiguration` — the collector sets `lifecycle_enabled` to `false`.

---

### Command 5: get-bucket-policy

**Resulting command:**

```
aws s3api get-bucket-policy --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[...]}"
}
```

**Response parsing:** The `Policy` field is a JSON-encoded string. The collector parses it into a JSON object and stores the parsed object as the `policy` key in the RecordData. The scalar `has_bucket_policy` is set to `true` if the policy exists. If no bucket policy is configured, the API returns `NoSuchBucketPolicy` — the collector sets `has_bucket_policy` to `false`.

---

### Command 6: get-bucket-location

**Resulting command:**

```
aws s3api get-bucket-location --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "LocationConstraint": null
}
```

**Response parsing:** Extract `LocationConstraint`. When `null` (us-east-1 buckets), normalize to the string `"us-east-1"`. Otherwise use the string value directly.

---

### Command 7: get-bucket-tagging _(only when `include_tagging` behavior is set)_

**Resulting command:**

```
aws s3api get-bucket-tagging --bucket prooflayer-demo-security-findings --output json
```

**Sample response:**

```json
{
  "TagSet": [
    { "Key": "Name", "Value": "prooflayer-demo-security-findings" },
    { "Key": "Environment", "Value": "demo" },
    { "Key": "ManagedBy", "Value": "terraform" },
    { "Key": "Owner", "Value": "cslone" }
  ]
}
```

**Response parsing:** The full response is stored under the `Tags` key in RecordData. Each tag is also flattened into a scalar field named `tag_key:<Key>` with the tag value as a string. If the bucket has no tags, the API returns `NoSuchTagSet` — the collector treats this as an empty tag set (not an error).

---

### Error Detection

the CLI exit code is checked. On non-zero exit, stderr is inspected for specific patterns:

| Stderr contains                              | Error variant                |
| -------------------------------------------- | ---------------------------- |
| `AccessDenied` or `UnauthorizedAccess`       | access-denied     |
| `InvalidParameterValue` or `ValidationError` | invalid-parameter |
| `does not exist` or `not found`              | resource-not-found |
| Anything else                                | command-failed    |

The following API errors are treated as **missing configuration** (not collection errors) and result in absent scalar fields rather than an error outcome:

| API Error                                        | Affected Command                   | Behavior                              |
| ------------------------------------------------ | ---------------------------------- | ------------------------------------- |
| `ServerSideEncryptionConfigurationNotFoundError` | get-bucket-encryption              | Fields absent                         |
| `NoSuchPublicAccessBlockConfiguration`           | get-public-access-block            | Fields absent                         |
| `NoSuchLifecycleConfiguration`                   | get-bucket-lifecycle-configuration | `lifecycle_enabled = false`           |
| `NoSuchBucketPolicy`                             | get-bucket-policy                  | `has_bucket_policy = false`           |
| `NoSuchTagSet`                                   | get-bucket-tagging                 | No tag fields collected, not an error |

If the bucket itself does not exist (e.g., `NoSuchBucket` from Command 1), the collector sets `found = false` and skips all remaining commands.

All other AWS CLI failures are reported as collection errors.

---

## Collected Data Fields

### Scalar Fields

| Field                     | Type    | Always Present                 | Source                                                                               |
| ------------------------- | ------- | ------------------------------ | ------------------------------------------------------------------------------------ |
| `found`                   | boolean | Yes                            | Derived — `true` if bucket exists                                                    |
| `bucket_name`             | string  | When found                     | Object field (echoed back for traceability)                                          |
| `region`                  | string  | When found                     | get-bucket-location → `LocationConstraint` (normalized, `null` → `us-east-1`)        |
| `versioning_status`       | string  | When found                     | get-bucket-versioning → `Status`                                                     |
| `sse_algorithm`           | string  | When found                     | get-bucket-encryption → `Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm`   |
| `kms_master_key_id`       | string  | When found                     | get-bucket-encryption → `Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID` |
| `bucket_key_enabled`      | boolean | When found                     | get-bucket-encryption → `Rules[0].BucketKeyEnabled`                                  |
| `block_public_acls`       | boolean | When found                     | get-public-access-block → `PublicAccessBlockConfiguration.BlockPublicAcls`           |
| `ignore_public_acls`      | boolean | When found                     | get-public-access-block → `PublicAccessBlockConfiguration.IgnorePublicAcls`          |
| `block_public_policy`     | boolean | When found                     | get-public-access-block → `PublicAccessBlockConfiguration.BlockPublicPolicy`         |
| `restrict_public_buckets` | boolean | When found                     | get-public-access-block → `PublicAccessBlockConfiguration.RestrictPublicBuckets`     |
| `lifecycle_enabled`       | boolean | When found                     | Derived — `true` if any enabled lifecycle rule exists                                |
| `has_bucket_policy`       | boolean | When found                     | Derived — `true` if a bucket policy exists                                           |
| `ssl_enforced`            | boolean | When found                     | Derived — `true` if policy contains a `Deny` + `aws:SecureTransport=false` statement |
| `tag_key:<Key>`           | string  | When found + `include_tagging` | One field per tag. E.g. `tag_key:Environment` → `"demo"`                             |

### RecordData Field

| Field      | Type       | Always Present | Description                                                                                                               |
| ---------- | ---------- | -------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `resource` | RecordData | Yes            | Merged configuration from all API calls. Empty `{}` when not found. `Tags` key only present when `include_tagging` is set |

---

## RecordData Structure

The `resource` field is built by merging all six API responses under named keys:

| Key | Source |
| --- | ------ |
| `Encryption` | get-bucket-encryption |
| `Versioning` | get-bucket-versioning |
| `PublicAccessBlock` | get-public-access-block |
| `Lifecycle` | get-bucket-lifecycle-configuration |
| `Policy` | get-bucket-policy (parsed from string) |
| `Location` | get-bucket-location |

### Top-level paths

| Path                                                                                                     | Type    | Example Value                                  |
| -------------------------------------------------------------------------------------------------------- | ------- | ---------------------------------------------- |
| `Encryption.ServerSideEncryptionConfiguration.Rules.0.ApplyServerSideEncryptionByDefault.SSEAlgorithm`   | string  | `"aws:kms"`                                    |
| `Encryption.ServerSideEncryptionConfiguration.Rules.0.ApplyServerSideEncryptionByDefault.KMSMasterKeyID` | string  | `"arn:aws:kms:us-east-1:486027077516:key/..."` |
| `Encryption.ServerSideEncryptionConfiguration.Rules.0.BucketKeyEnabled`                                  | boolean | `true`                                         |
| `Versioning.Status`                                                                                      | string  | `"Enabled"`                                    |
| `PublicAccessBlock.PublicAccessBlockConfiguration.BlockPublicAcls`                                       | boolean | `true`                                         |
| `PublicAccessBlock.PublicAccessBlockConfiguration.IgnorePublicAcls`                                      | boolean | `true`                                         |
| `PublicAccessBlock.PublicAccessBlockConfiguration.BlockPublicPolicy`                                     | boolean | `true`                                         |
| `PublicAccessBlock.PublicAccessBlockConfiguration.RestrictPublicBuckets`                                 | boolean | `true`                                         |
| `Lifecycle.Rules.0.Status`                                                                               | string  | `"Enabled"`                                    |
| `Lifecycle.Rules.0.ID`                                                                                   | string  | `"findings-retention"`                         |
| `Lifecycle.Rules.0.Expiration.Days`                                                                      | integer | `2555`                                         |
| `Lifecycle.Rules.0.Transitions.0.Days`                                                                   | integer | `90`                                           |
| `Lifecycle.Rules.0.Transitions.0.StorageClass`                                                           | string  | `"STANDARD_IA"`                                |
| `Lifecycle.Rules.0.Transitions.1.Days`                                                                   | integer | `365`                                          |
| `Lifecycle.Rules.0.Transitions.1.StorageClass`                                                           | string  | `"GLACIER"`                                    |
| `Policy.Version`                                                                                         | string  | `"2012-10-17"`                                 |
| `Policy.Statement.0.Sid`                                                                                 | string  | `"DenyNonSSL"`                                 |
| `Policy.Statement.0.Effect`                                                                              | string  | `"Deny"`                                       |
| `Location.LocationConstraint`                                                                            | string  | `null` (us-east-1) or region string            |

### Tags paths _(only when `include_tagging` behavior is set)_

| Path                  | Type   | Example Value                         |
| --------------------- | ------ | ------------------------------------- |
| `Tags.TagSet.0.Key`   | string | `"Name"`                              |
| `Tags.TagSet.0.Value` | string | `"prooflayer-demo-security-findings"` |
| `Tags.TagSet.1.Key`   | string | `"Environment"`                       |
| `Tags.TagSet.1.Value` | string | `"demo"`                              |

---

## State Fields

### Scalar State Fields

| State Field               | Type    | Allowed Operations              | Maps To Collected Field   |
| ------------------------- | ------- | ------------------------------- | ------------------------- |
| `found`                   | boolean | `=`, `!=`                       | `found`                   |
| `bucket_name`             | string  | `=`, `!=`, `contains`, `starts` | `bucket_name`             |
| `region`                  | string  | `=`, `!=`                       | `region`                  |
| `versioning_status`       | string  | `=`, `!=`                       | `versioning_status`       |
| `sse_algorithm`           | string  | `=`, `!=`                       | `sse_algorithm`           |
| `kms_master_key_id`       | string  | `=`, `!=`, `contains`, `starts` | `kms_master_key_id`       |
| `bucket_key_enabled`      | boolean | `=`, `!=`                       | `bucket_key_enabled`      |
| `block_public_acls`       | boolean | `=`, `!=`                       | `block_public_acls`       |
| `ignore_public_acls`      | boolean | `=`, `!=`                       | `ignore_public_acls`      |
| `block_public_policy`     | boolean | `=`, `!=`                       | `block_public_policy`     |
| `restrict_public_buckets` | boolean | `=`, `!=`                       | `restrict_public_buckets` |
| `lifecycle_enabled`       | boolean | `=`, `!=`                       | `lifecycle_enabled`       |
| `has_bucket_policy`       | boolean | `=`, `!=`                       | `has_bucket_policy`       |
| `ssl_enforced`            | boolean | `=`, `!=`                       | `ssl_enforced`            |
| `tag_key:<Key>`           | string  | `=`, `!=`, `contains`           | `tag_key:<Key>` (dynamic) |

### Behaviors

| Behavior          | Type | Description                                                                                                                                              |
| ----------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `include_tagging` | Flag | Collect bucket tags via `get-bucket-tagging`. Adds one API call. Off by default. Exposes `tag_key:<Key>` scalar fields and `Tags.TagSet.*` record paths. |

**Example usage in ESP:**

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
    behavior include_tagging
OBJECT_END
```

### Record Checks

The state field name `record` maps to the collected data field `resource`.

| State Field | Maps To Collected Field | Description                                      |
| ----------- | ----------------------- | ------------------------------------------------ |
| `record`    | `resource`              | Deep inspection of merged six-call configuration |

---

## Collection Strategy

| Property                     | Value                                                   |
| ---------------------------- | ------------------------------------------------------- |
| CTN Type               | `aws_s3_bucket`                                         |
| Collection Mode              | Content                                                 |
| Required Capabilities        | `aws_cli`, `s3_read`                                    |
| Expected Collection Time     | ~6000ms (six API calls); ~7000ms with `include_tagging` |
| Memory Usage                 | ~5MB                                                    |
| Network Intensive            | Yes                                                     |
| CPU Intensive                | No                                                      |
| Requires Elevated Privileges | No                                                      |
| Batch Collection             | No                                                      |

### Authentication

The `aws` CLI binary is invoked through a hardened command wrapper that clears the inherited environment; it relies on the AWS CLI's default credential chain:

1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`)
2. Shared credentials file (`~/.aws/credentials`)
3. IAM role (EC2, ECS, Lambda)
4. IRSA (EKS)

### Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetEncryptionConfiguration",
    "s3:GetBucketVersioning",
    "s3:GetBucketPublicAccessBlock",
    "s3:GetLifecycleConfiguration",
    "s3:GetBucketPolicy",
    "s3:GetBucketLocation"
  ],
  "Resource": "*"
}
```

### Collection Method Traceability

| Field       | Value                                                                                                                                                                |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| method_type | `ApiCall`                                                                                                                                                            |
| description | `"Query S3 bucket configuration via AWS CLI (6 API calls)"`                                                                                                          |
| target      | `"s3:<bucket_name>"`                                                                                                                                                 |
| command     | `"aws s3api get-bucket-encryption + get-bucket-versioning + get-public-access-block + get-bucket-lifecycle-configuration + get-bucket-policy + get-bucket-location"` |
| inputs      | `bucket_name` (always), `region` (when provided)                                                                                                                     |

---

## ESP Examples

### Security findings bucket fully hardened (KSI-MLA-OSM)

```esp
META
    esp_id `prooflayer-security-bucket-hardened`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `aws`
    criticality `high`
    control_mapping `NIST-800-53:AU-9,NIST-800-53:AU-4,NIST-800-53:SC-8,KSI:KSI-MLA-OSM`
    title `Security findings bucket tamper-resistant and encrypted`
META_END

DEF
    OBJECT security_bucket
        bucket_name `prooflayer-demo-security-findings`
        region `us-east-1`
    OBJECT_END

    STATE bucket_hardened
        found boolean = true
        versioning_status string = `Enabled`
        sse_algorithm string = `aws:kms`
        bucket_key_enabled boolean = true
        block_public_acls boolean = true
        ignore_public_acls boolean = true
        block_public_policy boolean = true
        restrict_public_buckets boolean = true
        lifecycle_enabled boolean = true
        has_bucket_policy boolean = true
        ssl_enforced boolean = true
    STATE_END

    CRI AND
        CTN aws_s3_bucket
            TEST all all AND
            STATE_REF bucket_hardened
            OBJECT_REF security_bucket
        CTN_END
    CRI_END
DEF_END
```

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
    region `us-east-1`
OBJECT_END

STATE bucket_hardened
    found boolean = true
    versioning_status string = `Enabled`
    sse_algorithm string = `aws:kms`
    bucket_key_enabled boolean = true
    block_public_acls boolean = true
    ignore_public_acls boolean = true
    block_public_policy boolean = true
    restrict_public_buckets boolean = true
    lifecycle_enabled boolean = true
    has_bucket_policy boolean = true
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF bucket_hardened
    OBJECT_REF security_bucket
CTN_END
```

### KMS key validation

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
    region `us-east-1`
OBJECT_END

STATE correct_kms_key
    found boolean = true
    sse_algorithm string = `aws:kms`
    kms_master_key_id string starts `arn:aws:kms:us-east-1:486027077516:`
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF correct_kms_key
    OBJECT_REF security_bucket
CTN_END
```

### Public access fully blocked

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
OBJECT_END

STATE no_public_access
    found boolean = true
    block_public_acls boolean = true
    ignore_public_acls boolean = true
    block_public_policy boolean = true
    restrict_public_buckets boolean = true
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF no_public_access
    OBJECT_REF security_bucket
CTN_END
```

### Record checks for deep inspection

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
    region `us-east-1`
OBJECT_END

STATE bucket_details
    found boolean = true
    record
        field Versioning.Status string = `Enabled`
        field Encryption.ServerSideEncryptionConfiguration.Rules.0.BucketKeyEnabled boolean = true
        field Encryption.ServerSideEncryptionConfiguration.Rules.0.ApplyServerSideEncryptionByDefault.SSEAlgorithm string = `aws:kms`
        field PublicAccessBlock.PublicAccessBlockConfiguration.BlockPublicAcls boolean = true
        field PublicAccessBlock.PublicAccessBlockConfiguration.RestrictPublicBuckets boolean = true
        field Lifecycle.Rules.0.Status string = `Enabled`
        field Lifecycle.Rules.0.Expiration.Days int = 2555
    record_end
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF bucket_details
    OBJECT_REF security_bucket
CTN_END
```

### KSI tag compliance validation

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
    region `us-east-1`
    behavior include_tagging
OBJECT_END

STATE ksi_tags_present
    found boolean = true
    tag_key:ManagedBy string = `terraform`
    tag_key:Environment string = `demo`
    tag_key:ksi-ksi-mla-osm string contains `SIEM`
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF ksi_tags_present
    OBJECT_REF security_bucket
CTN_END
```

### Record checks for tag deep inspection

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
    region `us-east-1`
    behavior include_tagging
OBJECT_END

STATE tag_details
    found boolean = true
    record
        field Tags.TagSet.0.Key string = `ksi-ksi-mla-osm`
    record_end
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF tag_details
    OBJECT_REF security_bucket
CTN_END
```

```esp
OBJECT security_bucket
    bucket_name `prooflayer-demo-security-findings`
OBJECT_END

STATE retention_compliant
    found boolean = true
    lifecycle_enabled boolean = true
    record
        field Lifecycle.Rules.0.Expiration.Days int = 2555
        field Lifecycle.Rules.0.Status string = `Enabled`
    record_end
STATE_END

CTN aws_s3_bucket
    TEST all all AND
    STATE_REF retention_compliant
    OBJECT_REF security_bucket
CTN_END
```

---

## Error Conditions

| Condition                              | Error Type                   | Outcome                                         | Notes                                                                    |
| -------------------------------------- | ---------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------ |
| Bucket does not exist (`NoSuchBucket`) | N/A (not an error)           | `found=false`                                   | `resource` set to empty `{}`, scalar fields absent                       |
| `bucket_name` missing from object      | Invalid object configuration | Error                                           | Required field — collector returns immediately                           |
| `aws` CLI binary not found             | Collection failed           | Error                                           | the `aws` CLI binary fails to spawn                                     |
| Invalid AWS credentials                | Collection failed           | Error                                           | CLI returns non-zero exit with credential error                          |
| IAM access denied                      | Collection failed           | Error                                           | stderr matched `AccessDenied` or `UnauthorizedAccess`                    |
| Encryption not configured              | N/A                          | Fields absent                                   | `sse_algorithm`, `kms_master_key_id`, `bucket_key_enabled` not collected |
| Public access block not configured     | N/A                          | Fields absent                                   | All four `block_*` / `restrict_*` fields not collected                   |
| No lifecycle configuration             | N/A                          | `lifecycle_enabled=false`                       | Lifecycle absent treated as disabled                                     |
| No bucket policy                       | N/A                          | `has_bucket_policy=false`, `ssl_enforced=false` | Both derived fields set to false                                         |
| No bucket tags (`NoSuchTagSet`)        | N/A                          | No tag fields collected                         | Only relevant when `include_tagging` is set                              |
| JSON parse failure                     | Collection failed           | Error                                           | the JSON in stdout cannot be parsed                                   |
| Incompatible CTN type                  | CTN type mismatch      | Error                                           | CTN type must match `aws_s3_bucket`                        |

### Validation Behavior

Validation requires the `found` field to be present in collected data. If missing, validation fails with a missing-data-field error.

When `found` is `false`:

- Scalar field checks against missing fields will **fail** (field not collected)
- Record checks will **fail** with message `"S3 bucket not found, cannot validate record checks"`

---

## Related CTN Types

| CTN Type                   | Relationship                                                        |
| -------------------------- | ------------------------------------------------------------------- |
| `aws_cloudtrail`           | CloudTrail delivers logs to S3; validate the destination bucket     |
| `aws_guardduty_detector`   | GuardDuty publishes findings to S3; validate the destination bucket |
| `aws_cloudwatch_log_group` | Alternative finding destination alongside S3                        |

---

## Scoped ESP Policy Example

```esp
DEF
    SET security_bucket_set union
        OBJECT t
            target `AWS::S3::Bucket`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE security_bucket_check
        found boolean = true
        versioning_status string = `Enabled`
        sse_algorithm string = `aws:kms`
        block_public_acls boolean = true
        ignore_public_acls boolean = true
        block_public_policy boolean = true
        restrict_public_buckets boolean = true
        ssl_enforced boolean = true
        lifecycle_enabled boolean = true
    STATE_END

    CRI AND
        CTN aws_s3_bucket_scoped
            TEST all all AND
            STATE_REF security_bucket_check
            SET_REF security_bucket_set
        CTN_END
    CRI_END
DEF_END
```

