# aws_vpc_scoped

## Overview

Scoped-injection variant of [`aws_vpc`](aws_vpc.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::EC2::Vpc` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_vpc_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `vpc_id` | `metadata.vpc_id` | **Yes** |
| `region` | `metadata.region` | No |

`target_asset_type`: `AWS::EC2::Vpc`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET vpcs union
    OBJECT t
        target `AWS::EC2::Vpc`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field    | Type   | Required | Description                                | Example                     |
| -------- | ------ | -------- | ------------------------------------------ | --------------------------- |
| `vpc_id` | string | No\*     | VPC ID for direct lookup                   | `vpc-051afae9e049b137a`     |
| `tags`   | string | No\*     | Tag filter in `Key=Value` format           | `Name=scanset-toy-boundary` |
| `region` | string | No       | AWS region override (passed as `--region`) | `us-east-1`                 |

\* At least one of `vpc_id` or `tags` must be specified. If neither is provided, the collector returns Invalid object configuration.

- If `vpc_id` is provided, it is passed as `--vpc-ids` for direct lookup.
- `tags` is parsed via `parse_tag_filter()` (splits on first `=`) and converted to a filter tuple `("tag:<Key>", "<Value>")`.
- Both can be provided — they are passed to the underlying `aws ec2 describe-vpcs` call together.
- If multiple VPCs match, a warning is logged and the **first result** is used.
- If `region` is omitted, the AWS CLI's default region resolution applies.

---

## Commands Executed

The collector internally builds and executes the AWS CLI commands shown below.

All commands are ultimately built by the `aws` CLI, which constructs a process via the `aws` CLI binary with arguments appended in this order:

```
aws <service> <operation> [--region <region>] --output json [additional args...]
```

### Command 1: describe-vpcs

Retrieves VPC configuration.

The command is built with these arguments:

- If `vpc_id` is provided: `--vpc-ids <vpc_id>`
- If tag filters are provided: `--filters Name=tag:<Key>,Values=<Value>`

**Resulting commands (examples):**

```
# By VPC ID
aws ec2 describe-vpcs --vpc-ids vpc-051afae9e049b137a --output json

# By tag
aws ec2 describe-vpcs --filters Name=tag:Name,Values=scanset-toy-boundary --output json

# With region
aws ec2 describe-vpcs --region us-east-1 --output json --vpc-ids vpc-051afae9e049b137a
```

**Response parsing:**

1. Extracts `response["Vpcs"]` as a JSON array
2. Each element is parsed into the fields below
3. If the array is empty, set `exists = false` and skip Commands 2 and 3

**Fields extracted:**

| Collected Field | Source JSON Key                      |
| --------------- | ------------------------------------ |
| `vpc_id` | `VpcId`                              |
| `cidr_block` | `CidrBlock`                          |
| `state` | `State`                              |
| `is_default` | `IsDefault`                          |
| `tag_name` | `Tags` array — finds `Key == "Name"` |

### Command 2: describe-vpc-attribute (enableDnsSupport)

Retrieves DNS support setting. **Only called if Command 1 found a VPC.**

**Resulting command:**

```
aws ec2 describe-vpc-attribute --vpc-id vpc-051afae9e049b137a --attribute enableDnsSupport --output json
```

**Response parsing:**

Extracts `response["EnableDnsSupport"]["Value"]` as a boolean. Defaults to `false` on failure (logged as a warning).

### Command 3: describe-vpc-attribute (enableDnsHostnames)

Retrieves DNS hostnames setting. **Only called if Command 1 found a VPC.**

**Resulting command:**

```
aws ec2 describe-vpc-attribute --vpc-id vpc-051afae9e049b137a --attribute enableDnsHostnames --output json
```

**Response parsing:**

Extracts `response["EnableDnsHostnames"]["Value"]` as a boolean. Defaults to `false` on failure (logged as a warning).

### DNS attribute failure behavior

If either `describe-vpc-attribute` call fails, the collector **does not** return an error. Instead, it logs a warning and defaults the value to `false`. This means a VPC with DNS support enabled could report `enable_dns_support = false` if the attribute API call fails due to permissions or timeouts.

### Error Detection

the CLI exit code is checked. On non-zero exit, stderr is inspected for specific patterns:

| Stderr contains                              | Error variant                |
| -------------------------------------------- | ---------------------------- |
| `AccessDenied` or `UnauthorizedAccess`       | access-denied     |
| `InvalidParameterValue` or `ValidationError` | invalid-parameter |
| `does not exist` or `not found`              | resource-not-found |
| Anything else                                | command-failed    |

This collector does **not** have special not-found error handling for the `describe-vpcs` call. An empty `Vpcs` array is the normal not-found case. Errors from `describe-vpc-attribute` are caught and logged as warnings, not propagated.

---

## Collected Data Fields

### Scalar Fields

| Field                  | Type    | Always Present       | Source                                                                          |
| ---------------------- | ------- | -------------------- | ------------------------------------------------------------------------------- |
| `exists`               | boolean | Yes                  | Derived — `true` if at least one VPC matched                                    |
| `vpc_id`               | string  | When exists          | `VpcId`                                          |
| `cidr_block`           | string  | When exists          | `CidrBlock`                                  |
| `state`                | string  | When exists          | `State`                                           |
| `is_default`           | boolean | When exists          | `IsDefault`                                  |
| `enable_dns_support`   | boolean | When exists          | `describe-vpc-attribute("enableDnsSupport")` — defaults to `false` on failure   |
| `enable_dns_hostnames` | boolean | When exists          | `describe-vpc-attribute("enableDnsHostnames")` — defaults to `false` on failure |
| `tag_name`             | string  | When Name tag exists | `Tags` array — `Name` tag value                                     |

**Key difference from other AWS contracts:** This contract uses `exists` (not `found`) as the existence field, and does not produce a `resource` RecordData field. There is no record check support.

### No RecordData Field

Unlike other AWS contracts, `aws_vpc` does not collect or produce a `resource` RecordData field. All validation is done through scalar state fields. For deep VPC inspection, use the related CTN types (`aws_subnet`, `aws_security_group`, `aws_route_table`, etc.).

---

## State Fields

| State Field            | Type    | Allowed Operations                               | Maps To Collected Field |
| ---------------------- | ------- | ------------------------------------------------ | ----------------------- |
| `exists`               | boolean | `=`, `!=`                                        | `exists`                |
| `vpc_id`               | string  | `=`, `!=`, `pattern_match`                       | `vpc_id`                |
| `cidr_block`           | string  | `=`, `!=`, `contains`, `starts`, `pattern_match` | `cidr_block`            |
| `state`                | string  | `=`, `!=`                                        | `state`                 |
| `is_default`           | boolean | `=`, `!=`                                        | `is_default`            |
| `enable_dns_support`   | boolean | `=`, `!=`                                        | `enable_dns_support`    |
| `enable_dns_hostnames` | boolean | `=`, `!=`                                        | `enable_dns_hostnames`  |
| `tag_name`             | string  | `=`, `!=`, `contains`, `pattern_match`           | `tag_name`              |

**Note:** This contract supports `pattern_match` on several string fields (`vpc_id`, `cidr_block`, `tag_name`), unlike most other AWS contracts. The full set of string operations is available for these fields.

---

## Collection Strategy

| Property                     | Value                 |
| ---------------------------- | --------------------- |
| CTN Type               | `aws_vpc`             |
| Collection Mode              | Custom(`api`)         |
| Required Capabilities        | `aws_api`, `ec2_read` |
| Expected Collection Time     | ~500ms                |
| Memory Usage                 | ~5MB                  |
| Network Intensive            | Yes                   |
| CPU Intensive                | No                    |
| Requires Elevated Privileges | No                    |
| Batch Collection             | No                    |

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
  "Action": ["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute"],
  "Resource": "*"
}
```

**Note:** Most other AWS contracts only need one IAM action. This one needs two because `DescribeVpcAttribute` is a separate API from `DescribeVpcs`. If the IAM policy only grants `DescribeVpcs`, the DNS fields will default to `false` with a warning.

### Collection Method Traceability

| Field       | Value                                       |
| ----------- | ------------------------------------------- |
| method_type | `ApiCall`                                   |
| description | `"Query VPC configuration via AWS EC2 API"` |
| target      | `"vpc:<vpc_id>"` or `"vpc:tag:<tags>"`      |
| command     | `"aws ec2 describe-vpcs"`                   |
| inputs      | `vpc_id`, `tags`, `region` (when provided)  |

---

## ESP Examples

### Basic VPC existence check

```esp
OBJECT my_vpc
    vpc_id `vpc-051afae9e049b137a`
OBJECT_END

STATE vpc_exists
    exists boolean = true
STATE_END

CTN aws_vpc
    TEST all all
    STATE_REF vpc_exists
    OBJECT_REF my_vpc
CTN_END
```

### VPC configuration validation

```esp
OBJECT boundary_vpc
    tags `Name=scanset-toy-boundary`
    region `us-east-1`
OBJECT_END

STATE vpc_properly_configured
    exists boolean = true
    enable_dns_support boolean = true
    enable_dns_hostnames boolean = true
    is_default boolean = false
STATE_END

CTN aws_vpc
    TEST all all
    STATE_REF vpc_properly_configured
    OBJECT_REF boundary_vpc
CTN_END
```

### Validate VPC is NOT the default

```esp
OBJECT production_vpc
    tags `Environment=production`
OBJECT_END

STATE not_default_vpc
    exists boolean = true
    is_default boolean = false
STATE_END

CTN aws_vpc
    TEST all all
    STATE_REF not_default_vpc
    OBJECT_REF production_vpc
CTN_END
```

### Validate CIDR block pattern

```esp
OBJECT internal_vpc
    vpc_id `vpc-051afae9e049b137a`
OBJECT_END

STATE uses_internal_cidr
    exists boolean = true
    cidr_block string starts `10.`
STATE_END

CTN aws_vpc
    TEST all all
    STATE_REF uses_internal_cidr
    OBJECT_REF internal_vpc
CTN_END
```

---

## Error Conditions

| Condition                                | Error Type                   | Outcome                 | Notes                                                 |
| ---------------------------------------- | ---------------------------- | ----------------------- | ----------------------------------------------------- |
| VPC not found                            | N/A (not an error)           | `exists=false`          | Scalar fields absent (except `exists`)                |
| Neither `vpc_id` nor `tags` specified    | Invalid object configuration | Error                   | At least one required                                 |
| `aws` CLI binary not found               | Collection failed           | Error                   | the `aws` CLI binary fails to spawn                  |
| Invalid AWS credentials                  | Collection failed           | Error                   | CLI returns non-zero exit with credential error       |
| IAM access denied (DescribeVpcs)         | Collection failed           | Error                   | stderr matched `AccessDenied` or `UnauthorizedAccess` |
| IAM access denied (DescribeVpcAttribute) | N/A (warning only)           | DNS defaults to `false` | Logged as warning, collection continues               |
| Invalid VPC ID format                    | Collection failed           | Error                   | AWS API rejects the ID                                |
| JSON parse failure                       | Collection failed           | Error                   | the JSON in stdout cannot be parsed                |
| Incompatible CTN type                    | CTN type mismatch      | Error                   | CTN type must match `aws_vpc`           |

### Validation Behavior

Validation requires the `exists` field to be present in collected data. If missing, validation fails with a missing-data-field error.

When `exists` is `false`, scalar field checks against missing fields will **fail** (field not collected).

---

## Related CTN Types

| CTN Type               | Relationship                        |
| ---------------------- | ----------------------------------- |
| `aws_subnet`           | Validates subnets within a VPC      |
| `aws_security_group`   | Validates security groups in a VPC  |
| `aws_route_table`      | Validates routing for a VPC         |
| `aws_internet_gateway` | Checks IGW attachment to VPC        |
| `aws_nat_gateway`      | NAT gateway placement in VPC        |
| `aws_flow_log`         | Validates VPC flow logs are enabled |

---

## Scoped ESP Policy Example

```esp
DEF
    SET boundary_vpc union
        OBJECT t
            target `AWS::EC2::Vpc`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    # VPC: non-default, private CIDR, DNS enabled
    STATE vpc_logical_network
        exists boolean = true
        is_default boolean = false
        state string = `available`
        enable_dns_support boolean = true
        enable_dns_hostnames boolean = true
        cidr_block string starts `10.`
    STATE_END

    CRI AND
        # VPC is non-default with private CIDR and DNS enabled
        CTN aws_vpc_scoped
            TEST all all AND
            STATE_REF vpc_logical_network
            SET_REF boundary_vpc
        CTN_END

    CRI_END
DEF_END
```

