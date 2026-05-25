# `gcp_sa_key`

GCP service account JSON key. Standard non-human GCP identity, downloaded
as a JSON file containing the private key + metadata for JWT-assertion
auth against Google's token endpoint.

## Status

**GCP discovery is not yet built.** The credential type exists so
credentials can be stored, but no discoverer or scanner currently
consumes them. A discovery that attempts to use one today is rejected
as unsupported.

When GCP discovery lands (future phase), this doc gets the per-scanner
"Used by" section filled in.

## What it represents

A GCP service account — non-human identity in a GCP project. The JSON
key file is the standard format Google provides when you create a
service account key in the Cloud Console. Auth flow: the SDK signs a
JWT assertion with the private key inside the JSON; Google issues a
short-lived access token.

## Payload fields

| Field      | Required | Description                                          |
|---         |---       |---                                                   |
| `key_json` | yes      | Full JSON key file content (secret)        |

The JSON itself contains:
- `type: "service_account"`
- `project_id`, `client_email`, `private_key_id`
- `private_key` (the actual signing key, in PEM-in-JSON-string form)
- `token_uri`, `auth_uri`, etc.

## Metadata fields (non-secret, operator-set)

| Key          | Purpose                                |
|---           |---                                     |
| `project_id` | GCP project ID the SA belongs to        |

## How to provision

In the GCP project that Prooflayer should scan:

```bash
# 1. Create the service account
gcloud iam service-accounts create prooflayer-scanner \
  --display-name="Prooflayer Scanner" \
  --project=<PROJECT_ID>

# 2. Grant least-privilege roles (start with Viewer)
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:prooflayer-scanner@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/viewer"

# 3. Generate + download the JSON key
gcloud iam service-accounts keys create prooflayer-scanner.json \
  --iam-account="prooflayer-scanner@<PROJECT_ID>.iam.gserviceaccount.com"
# → prooflayer-scanner.json is the file to paste
```

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (e.g. `gcp-prod-scanner`)
2. **Kind**: GCP service account
3. **Service account JSON**: paste the entire contents of the
   `.json` file (multi-line; PEM-with-newlines inside is fine)
4. **Metadata**: set `project_id`

## Rotation

Generate a new key, paste into the Rotate flow, then delete the old key:

```bash
gcloud iam service-accounts keys create new.json \
  --iam-account="prooflayer-scanner@<PROJECT_ID>.iam.gserviceaccount.com"
# Paste new.json into Prooflayer
# Verify next discovery sweep works
gcloud iam service-accounts keys delete <OLD_KEY_ID> \
  --iam-account="prooflayer-scanner@<PROJECT_ID>.iam.gserviceaccount.com"
```

Google does not auto-rotate SA keys. Quarterly rotation is typical;
some compliance regimes require monthly.

## Failure modes

(Will be populated when GCP discovery lands. Common failure modes
will include `permission denied` from missing IAM roles, `invalid_grant`
from clock skew on the Prooflayer VM, etc.)

## Security notes

- Service account JSON keys are highly sensitive — leaked, anyone can
  impersonate the SA from anywhere. Held as role-scoped plaintext at rest (no app-layer encryption).
- Prefer workload-identity-federation patterns (GitHub OIDC, AWS-to-GCP
  federation, etc.) over long-lived JSON keys when the deployment model
  supports them. For Prooflayer-on-VM today, JSON key is the practical
  pattern.
- Google logs all SA-key creation events; consider monitoring for
  unexpected new keys on the SA.
