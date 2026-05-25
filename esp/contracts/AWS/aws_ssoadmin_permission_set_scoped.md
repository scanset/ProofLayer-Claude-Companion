# aws_ssoadmin_permission_set_scoped

## Overview

Scoped-injection variant of [`aws_ssoadmin_permission_set`](aws_ssoadmin_permission_set.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::SSO::PermissionSet` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_ssoadmin_permission_set_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `permission_set_name` | `metadata.permission_set_name` | **Yes** |
| `instance_arn` | `metadata.instance_arn` | **Yes** |
| `region` | `metadata.region` | No |

`target_asset_type`: `AWS::SSO::PermissionSet`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET permissionsets union
    OBJECT t
        target `AWS::SSO::PermissionSet`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field                 | Type   | Required | Description                                | Example                                          |
| --------------------- | ------ | -------- | ------------------------------------------ | ------------------------------------------------ |
| `permission_set_name` | string | **Yes**  | Permission set name (exact match)          | `ProofLayerAdmin`                                |
| `instance_arn`        | string | **Yes**  | IAM Identity Center instance ARN           | `arn:aws:sso:::instance/ssoins-722365ac4d8ffe22` |
| `region`              | string | No       | AWS region override (passed as `--region`) | `us-east-1`                                      |

---

## Commands Executed

### Command 1: list-permission-sets + describe loop (ARN resolution)

The SSO Admin API provides no direct lookup by name. The collector calls `list-permission-sets` to get all ARNs, then calls `describe-permission-set` for each until finding one where `Name == permission_set_name`.

```
aws sso-admin list-permission-sets --instance-arn arn:aws:sso:::instance/ssoins-722365ac4d8ffe22 --output json
aws sso-admin describe-permission-set --instance-arn <arn> --permission-set-arn <ps-arn> --output json
# repeated until matching Name found
```

### Command 2: describe-permission-set

```
aws sso-admin describe-permission-set \
  --instance-arn arn:aws:sso:::instance/ssoins-722365ac4d8ffe22 \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-722365ac4d8ffe22/ps-ca776cd98f98270a \
  --output json
```

**Sample response:**

```json
{
  "PermissionSet": {
    "Name": "ProofLayerAdmin",
    "PermissionSetArn": "arn:aws:sso:::permissionSet/ssoins-722365ac4d8ffe22/ps-ca776cd98f98270a",
    "Description": "Full admin access to ProofLayer infrastructure",
    "CreatedDate": "2026-03-23T19:58:33.692000+00:00",
    "SessionDuration": "PT4H"
  }
}
```

### Command 3: list-managed-policies-in-permission-set

```
aws sso-admin list-managed-policies-in-permission-set \
  --instance-arn arn:aws:sso:::instance/ssoins-722365ac4d8ffe22 \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-722365ac4d8ffe22/ps-ca776cd98f98270a \
  --output json
```

**Sample responses:**

```json
{ "AttachedManagedPolicies": [{ "Name": "AdministratorAccess", "Arn": "arn:aws:iam::aws:policy/AdministratorAccess" }] }
{ "AttachedManagedPolicies": [] }
```

### Command 4: get-inline-policy-for-permission-set

```
aws sso-admin get-inline-policy-for-permission-set \
  --instance-arn arn:aws:sso:::instance/ssoins-722365ac4d8ffe22 \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-722365ac4d8ffe22/ps-66d746a2c9f78305 \
  --output json
```

**Sample responses:**

```json
{ "InlinePolicy": "{\"Statement\":[{\"Sid\":\"EC2ReadOnly\",...}],\"Version\":\"2012-10-17\"}" }
{ "InlinePolicy": "" }
```

Empty string = no inline policy. The collector parses the non-empty JSON string and stores the structured object under `InlinePolicy` in RecordData.

---

## Collected Data Fields

### Scalar Fields

| Field                  | Type    | Always Present | Source                                           |
| ---------------------- | ------- | -------------- | ------------------------------------------------ |
| `found`                | boolean | Yes            | Derived — `true` if permission set found by name |
| `permission_set_name`  | string  | When found     | `PermissionSet.Name`                             |
| `permission_set_arn`   | string  | When found     | ARN from list-permission-sets resolution         |
| `description`          | string  | When found     | `PermissionSet.Description`                      |
| `session_duration`     | string  | When found     | `PermissionSet.SessionDuration` (ISO 8601)       |
| `managed_policy_count` | integer | When found     | Derived — `len(AttachedManagedPolicies)`         |
| `has_inline_policy`    | boolean | When found     | Derived — `InlinePolicy` is non-empty string     |

### RecordData Field

| Field      | Type       | Always Present | Description                                                     |
| ---------- | ---------- | -------------- | --------------------------------------------------------------- |
| `resource` | RecordData | Yes            | Merged permission set + managed policies + parsed inline policy |

---

## RecordData Structure

```
PermissionSet.Name                        → "ProofLayerAdmin"
PermissionSet.PermissionSetArn            → "arn:aws:sso:::permissionSet/..."
PermissionSet.Description                 → "Full admin access to ProofLayer infrastructure"
PermissionSet.SessionDuration             → "PT4H"
AttachedManagedPolicies.0.Name            → "AdministratorAccess"
AttachedManagedPolicies.0.Arn             → "arn:aws:iam::aws:policy/AdministratorAccess"
AttachedManagedPolicies.*.Name            → (all managed policy names via wildcard)
InlinePolicy.Version                      → "2012-10-17"
InlinePolicy.Statement.0.Sid              → "EC2ReadOnly"
InlinePolicy.Statement.0.Effect           → "Allow"
InlinePolicy.Statement.1.Sid              → "SSMSessionManager"
InlinePolicy.Statement.2.Sid              → "LogsRead"
InlinePolicy.Statement.3.Sid              → "SecretsReadOnly"
```

---

## State Fields

| State Field            | Type       | Allowed Operations              | Maps To Collected Field |
| ---------------------- | ---------- | ------------------------------- | ----------------------- |
| `found`                | boolean    | `=`, `!=`                       | `found`                 |
| `permission_set_name`  | string     | `=`, `!=`                       | `permission_set_name`   |
| `permission_set_arn`   | string     | `=`, `!=`, `contains`, `starts` | `permission_set_arn`    |
| `description`          | string     | `=`, `!=`, `contains`, `starts` | `description`           |
| `session_duration`     | string     | `=`, `!=`                       | `session_duration`      |
| `managed_policy_count` | int        | `=`, `!=`, `>=`, `<=`, `>`, `<` | `managed_policy_count`  |
| `has_inline_policy`    | boolean    | `=`, `!=`                       | `has_inline_policy`     |
| `record`               | RecordData | (record checks)                 | `resource`              |

---

## Collection Strategy

| Property                     | Value                                   |
| ---------------------------- | --------------------------------------- |
| CTN Type               | `aws_ssoadmin_permission`           |
| Collection Mode              | Content                                 |
| Required Capabilities        | `aws_cli`, `sso_admin_read`             |
| Expected Collection Time     | ~6000ms (ARN resolution + three calls)  |
| Memory Usage                 | ~5MB                                    |
| Network Intensive            | Yes                                     |
| CPU Intensive                | No                                      |
| Requires Elevated Privileges | No                                      |
| Batch Collection             | No                                      |

### Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": [
    "sso:ListPermissionSets",
    "sso:DescribePermissionSet",
    "sso:ListManagedPoliciesInPermissionSet",
    "sso:GetInlinePolicyForPermissionSet"
  ],
  "Resource": "*"
}
```

---

## ESP Examples

### Admin permission set: 4-hour session, AdministratorAccess managed policy (KSI-IAM-JIT)

```esp
OBJECT admin_permission_set
    permission_set_name `ProofLayerAdmin`
    instance_arn `arn:aws:sso:::instance/ssoins-722365ac4d8ffe22`
    region `us-east-1`
OBJECT_END

STATE admin_ps_compliant
    found boolean = true
    session_duration string = `PT4H`
    managed_policy_count int = 1
    has_inline_policy boolean = false
    record
        field AttachedManagedPolicies.0.Name string = `AdministratorAccess`
    record_end
STATE_END

CTN aws_ssoadmin_permission
    TEST all all AND
    STATE_REF admin_ps_compliant
    OBJECT_REF admin_permission_set
CTN_END
```

### ReadOnly permission set: 2-hour session for auditors (KSI-IAM-ELP)

```esp
OBJECT readonly_permission_set
    permission_set_name `ProofLayerReadOnly`
    instance_arn `arn:aws:sso:::instance/ssoins-722365ac4d8ffe22`
    region `us-east-1`
OBJECT_END

STATE readonly_ps_compliant
    found boolean = true
    session_duration string = `PT2H`
    managed_policy_count int = 1
    has_inline_policy boolean = false
    record
        field AttachedManagedPolicies.0.Name string = `ReadOnlyAccess`
    record_end
STATE_END

CTN aws_ssoadmin_permission
    TEST all all AND
    STATE_REF readonly_ps_compliant
    OBJECT_REF readonly_permission_set
CTN_END
```

### Developer permission set: inline policy only, no managed policy (KSI-IAM-ELP)

```esp
OBJECT developer_permission_set
    permission_set_name `ProofLayerDeveloper`
    instance_arn `arn:aws:sso:::instance/ssoins-722365ac4d8ffe22`
    region `us-east-1`
OBJECT_END

STATE developer_ps_compliant
    found boolean = true
    session_duration string = `PT8H`
    managed_policy_count int = 0
    has_inline_policy boolean = true
    record
        field InlinePolicy.Statement.0.Sid string = `EC2ReadOnly`
        field InlinePolicy.Statement.1.Sid string = `SSMSessionManager`
    record_end
STATE_END

CTN aws_ssoadmin_permission
    TEST all all AND
    STATE_REF developer_ps_compliant
    OBJECT_REF developer_permission_set
CTN_END
```

---

## Error Conditions

| Condition                       | Error Type                   | Outcome       |
| ------------------------------- | ---------------------------- | ------------- |
| Permission set name not found   | N/A (not an error)           | `found=false` |
| `permission_set_name` missing   | Invalid object configuration | Error         |
| `instance_arn` missing          | Invalid object configuration | Error         |
| IAM access denied               | Collection failed           | Error         |
| `describe-permission-set` fails | Collection failed           | Error         |
| `list-managed-policies` fails   | Collection failed           | Error         |
| `get-inline-policy` fails       | Collection failed           | Error         |
| Incompatible CTN type           | CTN type mismatch      | Error         |

---

## Related CTN Types

| CTN Type                  | Relationship                                                       |
| ------------------------- | ------------------------------------------------------------------ |
| `aws_identitystore_group` | Groups are assigned to permission sets via account assignments     |
| `aws_iam_role`            | Permission sets provision temporary roles when sessions are active |

---

## Scoped ESP Policy Example

```esp
DEF
    # Permission set objects
    SET admin_ps union
        OBJECT t
            target `AWS::SSO::PermissionSet`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    # Admin: 4-hour session, AdministratorAccess managed policy, no inline
    STATE admin_ps_compliant
        found boolean = true
        session_duration string = `PT4H`
        managed_policy_count int >= 1
        has_inline_policy boolean = false
        record
            field AttachedManagedPolicies.0.Name string = `AdministratorAccess`
        record_end
    STATE_END

    CRI AND
        # Permission sets
        CTN aws_ssoadmin_permission_set_scoped
            TEST all all AND
            STATE_REF admin_ps_compliant
            SET_REF admin_ps
        CTN_END

    CRI_END
DEF_END
```

