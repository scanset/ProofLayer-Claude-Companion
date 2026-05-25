# API Reference

Prooflayer's **HTTP router** (`127.0.0.1:3000`, loopback, nginx-proxied) serves
everything the operator console and the CMR oversight surface use — it's the
product's public interface. (The server also binds a `:3443` TLS listener, but
it is **unused in the agentless alpha**.)

> Through the alpha container you reach the API over plain HTTP via nginx on the
> published operator port — examples below use `http://localhost:8080` (the
> default `-p 8080:80` mapping; adjust to yours). The **CMR read API** is on the
> separate `:8081` port (e.g. `http://localhost:9090` from `-p 9090:8081`).

---

## Auth models

| Identity | Used by | How you get it |
|---|---|---|
| **Operator session** | system-ui (`/api/*`, `/api/admin/*`) | session token from `POST /system-ui/auth/login`. |
| **CMR viewer** | CMR oversight (`/cmr-api/*`) | API key, scope `CmrViewer` — issued by an admin. The key an AO (or an AI assistant acting for the user) uses to read the evidence. |
| **(none)** | `/health`, `/verify` | Public. |

Most write operations on `/api/*` additionally require the admin capability on
the operator session.

### Logging in

```bash
curl -X POST http://localhost:8080/system-ui/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"super-admin","password":"prooflayer"}'
# → { "token": "<JWT>", "expires_at": "...", "permissions": {...} }

TOKEN=<JWT from above>
curl http://localhost:8080/api/inventory/credentials \
  -H "Authorization: Bearer $TOKEN"
```

---

## HTTP router — route map (the groups you'll use)

| Group | Purpose |
|---|---|
| `POST /system-ui/auth/login`, `GET /me`, `DELETE /session`, `DELETE /sessions/{id}` | System-ui session lifecycle (single super-admin model — no password change or bootstrap-finalize). |
| `/api/admin/*` | persistent keys (incl. the CMR viewer key), findings, frameworks. |
| `/api/inventory/credentials` | Credential CRUD + rotate. (`POST`/`GET`/`GET {id}`/`PUT {id}/rotate`/`DELETE {id}`) |
| `/api/inventory/assets` | Asset CRUD + `scan-now`, `enumerate` (host SSH inventory), graph links, provider-override. |
| `/api/inventory/policies` | Policy registry from the `.esp` tree: `bulk-register`, list/get, retire, `scan-now`. |
| `/api/inventory/asset-policies` | Asset↔policy linking: link/unlink, `auto-link`, status transition, `schedule`. |
| `/api/inventory/discover/*` | `local`, `m365`, `m365_purview`, `m365_pwsh`, `k8s/local`, `k8s/aks`, `k8s/eks`, `network`. |
| `/api/inventory/test-scan` | One-asset dispatch with inline result (no persistence). |
| `/api/inventory/scan-now/batch` | Parallel multi-asset dispatch. |
| `/api/inventory/scan-runs` | Run history list/detail + `replay`. |
| `/api/inventory/evidence/*` | `subjects`, `posture-history`, `state-chain`, `ctn-drift`, `findings`, `findings-summary`, `ctn-results`, `verify-hash`, `reproducibility`. |
| `/api/inventory/vuln/*` | CVE catalog, VDR findings list/detail/update, remediation decisions. |
| `/api/inventory/pathfinder/graph` | Risk-neighborhood graph around a `focus` asset (`depth` 1–5). Nodes carry open-finding risk; edges are discovered linkage. |
| `/api/transparency/*` | `tree-summary`, `entries`, per-entry envelopes/verifications/dispatches, `proof/{index}`, `checkpoints`. (operator-gated) |
| `/verify` | Replay-hash lookup utility (powers the `/verify` page). |
| `/health` | Liveness (no auth). |
| `/cmr-api/*` | AO read-only oversight: `summary`, `evidence/by-asset`, `assets/*`, `hosts`, `findings`, `controls`, `vdr/*`, `esp-policies` + `contracts` (source inspection), `transparency/*`, `verify/{replay_hash}` (on-demand replay-hash reproduction), `identity/{key_id}` (signer public key + cert chain). (CMR viewer key) |

---

## Worked example — credential → discover → scan

```bash
TOKEN=...   # from login above
BASE=http://localhost:8080

# 1. Add an SSH credential
curl -X POST $BASE/api/inventory/credentials -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{
    "name":"demo-ssh","kind":"ssh_key",
    "payload":{"kind":"ssh_key","private_key_pem":"-----BEGIN OPENSSH PRIVATE KEY-----\n..."}
  }'

# 2. Create an asset (or discover)
curl -X POST $BASE/api/inventory/assets -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{
    "asset_type":"linux_host","display_name":"demo-vm","external_asset_id":"demo-vm",
    "metadata":{"hostname":"10.0.0.5"}
  }'

# 3. Register + link a policy, then test-scan the asset
curl -X POST $BASE/api/inventory/test-scan -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{ "asset_id":"<id>", "policy_path":"R9/ksi_cna_ibp_r9_selinux.esp" }'

# 4. Read the proof + verify the hash
curl "$BASE/api/inventory/scan-runs" -H "Authorization: Bearer $TOKEN"
curl "$BASE/api/inventory/evidence/verify-hash?hash=<replay_hash>" -H "Authorization: Bearer $TOKEN"
```

> Request/response bodies evolve in this dev workspace. Before scripting against
> a route, confirm the handler signature in
> the running server. The route groups below are stable;
> exact field names may not be.
