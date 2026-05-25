# aws_cloudwatch_metric_filter_scoped

## Overview

Scoped-injection variant of [`aws_cloudwatch_metric_filter`](aws_cloudwatch_metric_filter.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** (reused verbatim) — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `AWS::Logs::MetricFilter` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `aws_cloudwatch_metric_filter_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `filter_name` | `metadata.filter_name` | **Yes** |
| `log_group_name` | `metadata.log_group_name` | **Yes** |
| `region` | `metadata.region` | No |

`target_asset_type`: `AWS::Logs::MetricFilter`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET metricfilters union
    OBJECT t
        target `AWS::Logs::MetricFilter`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field            | Type   | Required | Description                                | Example                       |
| ---------------- | ------ | -------- | ------------------------------------------ | ----------------------------- |
| `filter_name`    | string | **Yes**  | Metric filter name (exact match)           | `prooflayer-demo-root-login`  |
| `log_group_name` | string | **Yes**  | Log group the filter is attached to        | `/prooflayer-demo/cloudtrail` |
| `region`         | string | No       | AWS region override (passed as `--region`) | `us-east-1`                   |

---

## Commands Executed

### Command 1: describe-metric-filters

```
aws logs describe-metric-filters \
  --log-group-name /prooflayer-demo/cloudtrail \
  --filter-name-prefix prooflayer-demo-root-login \
  --output json
```

The collector then applies an exact match on `filterName == filter_name` from the results.

**Sample response:**

```json
{
  "metricFilters": [
    {
      "filterName": "prooflayer-demo-root-login",
      "filterPattern": "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }",
      "metricTransformations": [
        {
          "metricName": "RootLoginCount",
          "metricNamespace": "ProofLayer/Security",
          "metricValue": "1",
          "unit": "None"
        }
      ],
      "creationTime": 1774369676964,
      "logGroupName": "/prooflayer-demo/cloudtrail",
      "applyOnTransformedLogs": false
    }
  ]
}
```

---

## Collected Data Fields

### Scalar Fields

| Field              | Type    | Always Present | Source                                      |
| ------------------ | ------- | -------------- | ------------------------------------------- |
| `found`            | boolean | Yes            | Derived — `true` if exact filter name match |
| `filter_name`      | string  | When found     | `filterName`                                |
| `log_group_name`   | string  | When found     | `logGroupName`                              |
| `filter_pattern`   | string  | When found     | `filterPattern`                             |
| `metric_name`      | string  | When found     | `metricTransformations[0].metricName`       |
| `metric_namespace` | string  | When found     | `metricTransformations[0].metricNamespace`  |

### RecordData Field

| Field      | Type       | Always Present | Description                                   |
| ---------- | ---------- | -------------- | --------------------------------------------- |
| `resource` | RecordData | Yes            | Full filter object. Empty `{}` when not found |

---

## RecordData Structure

```
filterName                                → "prooflayer-demo-root-login"
logGroupName                              → "/prooflayer-demo/cloudtrail"
filterPattern                             → "{ $.userIdentity.type = \"Root\" ... }"
metricTransformations.0.metricName        → "RootLoginCount"
metricTransformations.0.metricNamespace   → "ProofLayer/Security"
metricTransformations.0.metricValue       → "1"
applyOnTransformedLogs                    → false
```

---

## State Fields

| State Field        | Type       | Allowed Operations              | Maps To Collected Field |
| ------------------ | ---------- | ------------------------------- | ----------------------- |
| `found`            | boolean    | `=`, `!=`                       | `found`                 |
| `filter_name`      | string     | `=`, `!=`                       | `filter_name`           |
| `log_group_name`   | string     | `=`, `!=`                       | `log_group_name`        |
| `filter_pattern`   | string     | `=`, `!=`, `contains`, `starts` | `filter_pattern`        |
| `metric_name`      | string     | `=`, `!=`                       | `metric_name`           |
| `metric_namespace` | string     | `=`, `!=`                       | `metric_namespace`      |
| `record`           | RecordData | (record checks)                 | `resource`              |

---

## Collection Strategy

| Property                 | Value                                    |
| ------------------------ | ---------------------------------------- |
| CTN Type           | `aws_cloudwatch_metric_filter`           |
| Collection Mode          | Metadata                                 |
| Required Capabilities    | `aws_cli`, `cloudwatch_logs_read`        |
| Expected Collection Time | ~1500ms                                  |
| Memory Usage             | ~2MB                                     |
| Batch Collection         | No                                       |

### Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": ["logs:DescribeMetricFilters"],
  "Resource": "*"
}
```

---

## ESP Examples

### Root login metric filter exists (KSI-MLA-OSM, KSI-CMT-LMC)

```esp
OBJECT root_login_filter
    filter_name `prooflayer-demo-root-login`
    log_group_name `/prooflayer-demo/cloudtrail`
    region `us-east-1`
OBJECT_END

STATE filter_compliant
    found boolean = true
    metric_name string = `RootLoginCount`
    metric_namespace string = `ProofLayer/Security`
STATE_END

CTN aws_cloudwatch_metric_filter
    TEST all all AND
    STATE_REF filter_compliant
    OBJECT_REF root_login_filter
CTN_END
```

---

## Error Conditions

| Condition                            | Error Type                   | Outcome       |
| ------------------------------------ | ---------------------------- | ------------- |
| Filter not found                     | N/A (not an error)           | `found=false` |
| `filter_name` missing from object    | Invalid object configuration | Error         |
| `log_group_name` missing from object | Invalid object configuration | Error         |
| IAM access denied                    | Collection failed           | Error         |
| Incompatible CTN type                | CTN type mismatch      | Error         |

---

## Related CTN Types

| CTN Type                      | Relationship                                               |
| ----------------------------- | ---------------------------------------------------------- |
| `aws_cloudwatch_metric_alarm` | Alarms fire based on metrics produced by these filters     |
| `aws_cloudwatch_log_group`    | Filters are attached to log groups                         |
| `aws_cloudtrail`              | CloudTrail delivers logs to the group this filter monitors |

---

## Scoped ESP Policy Example

```esp
DEF
    # Metric filter objects
    SET root_login_filter union
        OBJECT t
            target `AWS::Logs::MetricFilter`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    # Root login filter: specific metric name
    STATE root_login_filter_compliant
        found boolean = true
        metric_name string = `RootLoginCount`
    STATE_END

    CRI AND
        # Root login filter
        CTN aws_cloudwatch_metric_filter_scoped
            TEST all all AND
            STATE_REF root_login_filter_compliant
            SET_REF root_login_filter
        CTN_END

    CRI_END
DEF_END
```

