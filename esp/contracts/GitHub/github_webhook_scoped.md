# github_webhook_scoped

## Overview

Scoped-injection variant of [`github_webhook`](github_webhook.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `SDLC::Webhook` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `github_webhook_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `owner` | `metadata.owner` | **Yes** |
| `repo` | `metadata.repo` | **Yes** |
| `webhook_id` | `metadata.github_id` | **Yes** |

`target_asset_type`: `SDLC::Webhook`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET webhooks union
    OBJECT t
        target `SDLC::Webhook`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field        | Type    | Required | Description                                     | Example                  |
| ------------ | ------- | -------- | ----------------------------------------------- | ------------------------ |
| `owner`      | string  | **Yes**  | Owner login.                                    | `scanset`                |
| `repo`       | string  | **Yes**  | Repo name.                                      | `Endpoint-State-Policy`  |
| `webhook_id` | integer | **Yes**  | Numeric webhook id from GitHub.                  | `42`                     |

---

## Commands Executed

```
GET https://api.github.com/repos/{owner}/{repo}/hooks/{webhook_id}
Headers:
  Authorization: Bearer <GITHUB_TOKEN>
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

**Requires PAT scope:** `Repository: Webhooks: Read`.

**Sample response (abbreviated):**

```json
{
  "id": 42,
  "type": "Repository",
  "name": "web",
  "active": true,
  "events": ["push", "pull_request"],
  "config": {
    "content_type": "json",
    "insecure_ssl": "0",
    "url": "https://hook-receiver.example.com/x",
    "secret": "********"
  },
  "last_response": {
    "code": 200,
    "status": "active",
    "message": "OK"
  }
}
```

**Notes on the wire shape:**
- `config.insecure_ssl` is a **string** (`"0"` or `"1"`), not a bool.
- `config.secret`, when set, is masked as `"********"`. Its absence in
  the response means no secret is configured.
- An empty array `[]` from `GET /repos/.../hooks` means no webhooks
  exist on this repo. The list-form endpoint is used during discovery
  to enumerate webhooks; this CTN consumes the per-id endpoint.

---

## Collected Data Fields

| Field                  | Type    | Always Present | Source                                                                          |
| ---------------------- | ------- | -------------- | ------------------------------------------------------------------------------- |
| `found`                | boolean | Yes            | `true` on HTTP 200                                                              |
| `active`               | boolean | When found     | `active`                                                                        |
| `uses_https`           | boolean | When found     | `true` iff `config.url` starts with `https://`                                  |
| `ssl_verify_enabled`   | boolean | When found     | `true` iff `config.insecure_ssl == "0"` (or absent)                             |
| `secret_configured`    | boolean | When found     | `true` iff `config.secret` is present in the response                           |
| `url`                  | string  | When found     | `config.url`                                                                    |
| `content_type`         | string  | When found     | `config.content_type` ("form" \| "json")                                        |
| `last_response_status` | string  | When found     | `last_response.status` ("active" \| "deactivated" \| "invalid" \| "unknown")    |
| `last_response_code`   | integer | When found     | `last_response.code`, or `0` if never delivered                                 |

---

## State Fields

| State Field            | Type    | Allowed Operations                |
| ---------------------- | ------- | --------------------------------- |
| `found`                | boolean | `=`, `!=`                         |
| `active`               | boolean | `=`, `!=`                         |
| `uses_https`           | boolean | `=`, `!=`                         |
| `ssl_verify_enabled`   | boolean | `=`, `!=`                         |
| `secret_configured`    | boolean | `=`, `!=`                         |
| `url`                  | string  | `=`, `!=`                         |
| `content_type`         | string  | `=`, `!=`                         |
| `last_response_status` | string  | `=`, `!=`                         |
| `last_response_code`   | int     | `=`, `!=`, `<`, `<=`, `>`, `>=`   |

---

## Failure Modes

| HTTP status | CTN behavior                                                                |
| ----------- | --------------------------------------------------------------------------- |
| 200         | All fields populated.                                                       |
| 401         | `CollectionError`.                                                          |
| 403         | `found=false`, warning attached. PAT lacks `Webhooks: Read`.                |
| 404         | `found=false`, warning attached. Webhook was deleted between discovery + scan. |
| 5xx / 429   | Retry-with-backoff, then `found=false`.                                     |

---

## Collection Strategy

| Property                 | Value                                            |
| ------------------------ | ------------------------------------------------ |
| Collector ID             | `github_webhook_collector`                       |
| Collector Type           | `github_webhook`                                 |
| Collection Mode          | Metadata                                         |
| Required Capabilities    | `github_pat_env`, `github_webhooks_read`         |
| Required Env Vars        | `GITHUB_TOKEN`, `GITHUB_BASE_URL` (optional)     |
| Expected Collection Time | ~300ms                                           |

---

## Control Mapping (sample)

| Field check                  | Control(s)                                |
| ---------------------------- | ----------------------------------------- |
| `uses_https = false`         | CMMC SC.L2-3.13.8, NIST SC-8 / SC-8(1)    |
| `ssl_verify_enabled = false` | NIST SC-8, SC-23 (transport integrity)    |
| `secret_configured = false`  | NIST IA-5 (signature-based authn of payloads) |
| `last_response_status = "invalid"` | operational hygiene — broken webhook leaking events into the void |

---

## Scoped ESP Policy Example

```esp
DEF
    SET github_webhooks union
        OBJECT t
            target `SDLC::Webhook`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE webhook_ssl_verified
        found boolean = true
        ssl_verify_enabled boolean = true
    STATE_END

    CRI AND
        CTN github_webhook_scoped
            TEST all all AND
            STATE_REF webhook_ssl_verified
            SET_REF github_webhooks
        CTN_END
    CRI_END
DEF_END
```

