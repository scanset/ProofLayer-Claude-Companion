# `aws_access_key`

Static IAM-user access key. The simplest AWS auth flow — same shape as
`~/.aws/credentials` with `aws_access_key_id` + `aws_secret_access_key`.

## What it represents

An AWS IAM user identity. The credential authenticates Prooflayer's
scanner directly *as that user* against AWS APIs. Best for tenants
without an existing role-assumption pattern; rotate to `aws_role`
when you onboard a 3PAO-shaped customer flow.

## Payload fields

| Field               | Required | Description                                              |
|---                  |---       |---                                                       |
| `access_key_id`     | yes      | IAM access key id (`AKIA…` for users, `ASIA…` for STS)   |
| `secret_access_key` | yes      | Matching secret (secret)                       |

## Metadata fields (non-secret, operator-set)

| Key             | Purpose                                                       |
|---              |---                                                            |
| `region`        | Default AWS region for SDK calls. Sets `AWS_DEFAULT_REGION`.   |
| `account_alias` | Human label for the account (e.g. `prod`, `customer-acme`)    |

## How to provision

In the AWS account that Prooflayer should scan:

```bash
# Create the IAM user (least-privilege starting point: ReadOnlyAccess)
aws iam create-user --user-name prooflayer-scanner
aws iam attach-user-policy --user-name prooflayer-scanner \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

# Generate the access key — note the SecretAccessKey (it's only shown once)
aws iam create-access-key --user-name prooflayer-scanner
```

The output prints both halves. Paste them into Prooflayer immediately
— AWS does not let you re-display the secret later, only re-generate.

For terraform-managed setup, see the credential fixtures ([test_fixtures/credentials/](../../test_fixtures/credentials/README.md))
if present; otherwise the four-line CLI block above is sufficient.

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive label (e.g. `scanset-aws-prod`)
2. **Kind**: AWS access key
3. **Access key ID**: paste `AKIA…`
4. **Secret access key**: paste the matching secret
5. **Metadata**: at minimum set `region` and `account_alias`
6. **Expires at**: optional — set to your rotation deadline if you
   want UI countdown reminders

## Used by

- AWS Resource Explorer discovery (Phase 2)
- Any host scan dispatched via the AWS SSM channel (the channel reuses
  this credential to call SSM to start a session)
- **EKS cluster discovery + container scanning** — see next section.

## EKS — cluster discovery + container scanning

The same `aws_access_key` doubles as the Kubernetes credential for EKS —
no separate `kube_config`. Prooflayer mints the apiserver connection
in-process: no stored kubeconfig, no `aws eks get-token` exec provider.
Used by both EKS internals discovery and container scanning.

**Why an access key and not a role for EKS.** Prooflayer runs *only the
credential it is given* — it does not read ambient process-env or
instance-profile identity. An `aws_role` credential is therefore not
self-contained for the in-process apiserver-connection path: a role isn't
credentials, it's something an identity assumes, and there's no ambient
source identity to do the assuming. The `aws_access_key` IS the identity,
so it works directly — the presigned-STS bearer carries the IAM user, and
the EKS access entry maps that user. (A role would only work where
Prooflayer has a source identity to assume from — an EC2 instance profile
— which isn't supported on this path yet.)

The connection works by:

1. `eks:DescribeCluster` → apiserver endpoint + base64-PEM CA bundle.
2. A presigned `sts:GetCallerIdentity` URL, base64url-encoded behind
   `k8s-aws-v1.` — the apiserver bearer, exactly what `aws eks get-token`
   produces. The signed `x-k8s-aws-id` header binds the token to one
   cluster.

### Required permissions

**AWS IAM (control plane)** — the user needs:

| Action | Source | Why |
|---     |---     |---  |
| `eks:DescribeCluster` | `SecurityAudit` managed policy (already attached) | fetch apiserver endpoint + CA (step 1) |
| `sts:GetCallerIdentity` | allowed for every principal by default | the presigned bearer (step 2) |

No EKS-specific IAM policy is needed beyond `SecurityAudit`. Authorization
to read resources / exec into pods is the Kubernetes RBAC layer below.

**EKS access entry + Kubernetes RBAC (data plane)** — the cluster must use
`authentication_mode = "API"` (or `API_AND_CONFIG_MAP`). See
your EKS Terraform:

- An **access entry** maps the IAM user ARN
  (`arn:aws:iam::<acct>:user/prooflayer-scanner`) to the Kubernetes group
  `prooflayer:scanners`, with **no** AWS-managed access policy associated.
- A `prooflayer-scanner` ClusterRole + ClusterRoleBinding grants that group
  its authority — BYTE-IDENTICAL to the AKS and rocky-k3s rigs:

  | Tier | Resources | Verbs |
  |---   |---        |---    |
  | Discovery | `namespaces`, `nodes`, `serviceaccounts`, `pods`; `apps/{deployments,statefulsets,daemonsets}`; `batch/{jobs,cronjobs}`; `rbac/*` | `get`, `list`, `watch` |
  | Scan (container exec) | `pods/exec` | `get`, `create` |

Both `get` **and** `create` on `pods/exec` are required: WebSocket exec
(Prooflayer's container-exec channel) authorizes as `get`, SPDY exec as `create`.

AWS-managed access policies (`AmazonEKSViewPolicy` etc.) are NOT used —
`View` does not grant `pods/exec`, so it can't cover the scan tier.

### Adding in Prooflayer

No new credential — reuse the existing `aws_access_key`. On the EKS
container asset, assign the `aws_access_key` cred + the container-exec
channel; Prooflayer walks the asset graph to the parent cluster, reads its
EKS cluster ARN (region + name parsed from it), and runs the DescribeCluster
+ presign above. Discovery links the Kubernetes cluster asset to its EKS
cluster asset automatically.

## Rotation

No automatic expiry. Rotate quarterly or on IAM policy change:

```bash
# Create new key
aws iam create-access-key --user-name prooflayer-scanner
# Paste new key into Prooflayer's "Rotate" form on the credential card
# Wait for one discovery cycle to verify new key works
# Delete old key
aws iam delete-access-key --user-name prooflayer-scanner --access-key-id AKIAOLD…
```

## Failure modes

| Symptom                                            | Likely cause                                                       |
|---                                                 |---                                                                 |
| `InvalidClientTokenId`                              | Access key id was deleted or never existed                          |
| `SignatureDoesNotMatch`                             | Secret access key mismatch (paste error, line-wrapping)             |
| `AccessDenied` on specific resources                | IAM policy is missing read perms; check the policy attached         |
| `ThrottlingException` during multi-region discovery | Discovery cadence too aggressive for your service quotas             |
| EKS: `no ambient AWS source credentials...` on discovery/scan | Used an `aws_role` credential; EKS needs the self-contained `aws_access_key` (see EKS section) |
| EKS: apiserver 401 on discovery/scan                | IAM user ARN not mapped in an EKS access entry, or the cluster region ≠ the credential's `region` metadata (the STS presign is region-scoped) |
| EKS: `pods/exec` 403 mid-exec-handshake             | ClusterRoleBinding's `pods/exec` rule missing `get` (WebSocket) or `create` (SPDY) — grant both |

## Security notes

- Pinned IAM user is a static credential. Prefer `aws_role` for any
  cross-account / 3PAO scenario where you don't own both sides.
- Secret access key is held as role-scoped plaintext at rest (no app-layer
  encryption) and never logged.
- Consider attaching an IAM Condition restricting the user to specific
  source IPs (the Prooflayer VM's egress IP).
- For high-sensitivity tenants, rotate to `aws_role` and put the source
  identity on the Prooflayer VM's instance profile.
