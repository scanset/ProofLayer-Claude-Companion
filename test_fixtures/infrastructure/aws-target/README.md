# aws-target — minimal AWS scan target (drift by design)

Two S3 buckets that give a scan **both** a pass and a fail, so you can see
Prooflayer flag a real misconfiguration end-to-end:

| Bucket | Config | Expected |
|---|---|---|
| `…-compliant-<rand>` | AES256 encryption + versioning + public-access block + TLS-only bucket policy | **pass** |
| `…-drift-<rand>` | no default encryption, versioning off, public-access block **disabled** | **fail** |

No objects are ever made public — the **configuration** is the finding, so this
is safe to run in any account you're authorized to use.

## Deploy

Auth uses your ambient AWS context (env vars, shared config, or an instance
role). From this directory:

```bash
cp terraform.tfvars.example terraform.tfvars   # optional: set region / profile / name_prefix
terraform init
terraform apply
terraform output                               # bucket names + region
```

## Point Prooflayer at it

1. Provision a read-only AWS credential with the
   [aws-iam](../../credentials/aws-iam/README.md) fixture and register it in
   Prooflayer (kind `aws_access_key` or `aws_role`).
2. Either run **AWS discovery** (it enumerates the buckets as assets), or
   register the two bucket names from `terraform output` directly.
3. Link/auto-link the bundled `aws_s3_bucket` policy and scan.
4. You should see the compliant bucket **pass** and the drift bucket **fail** —
   a signed, replayable proof of each verdict. (Workflow:
   [../../../usage/workflows/scanning-and-evidence.md](../../../usage/workflows/scanning-and-evidence.md).)

## Tear down

```bash
terraform destroy
```

`force_destroy = true` is set on both buckets so destroy succeeds even if a scan
or you put test objects in them.
