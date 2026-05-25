# Test Fixtures — Real Targets to Scan

To evaluate Prooflayer you need something to scan. The fastest path needs no
credentials at all (the local channel). For a realistic demo, deploy purpose-built
**Terraform fixtures** that stand up real targets — with deliberate
misconfigurations baked in — so findings actually appear.

> Terraform fixtures create **billable cloud resources** — `terraform destroy`
> when done. The eval-specific Terraform lives in this guide's two fixture
> subfolders (below); deploy from there.

---

## Fixture folders

Purpose-built, eval-specific Terraform lives in two subfolders (separating the
secret from the target — see [components/inventory.md](../components/inventory.md)):

| Folder | Holds |
|---|---|
| [credentials/](credentials/README.md) | Ready-to-apply Terraform for read-only credentials: **azure-spn** (yields all three Azure credential kinds) and **aws-iam** (role/key). |
| [infrastructure/](infrastructure/README.md) | Ready-to-apply drift-by-design scan targets: **azure-target** (storage) and **aws-target** (two S3 buckets). |
| [suggestions.md](suggestions.md) | **What to test next** — a progression of further fixtures to try (cloud → Kubernetes `kind` → AKS/EKS → breadth). The assistant offers one relevant suggestion after a step. |

Deploy a credential from `credentials/`, then its matching target from
`infrastructure/`, then scan. Each subfolder's README states what to deploy and
how to wire its outputs into Prooflayer. When you've got the basics working,
[suggestions.md](suggestions.md) points you at the next thing to try.

---

## Tier 0 — No cloud, no Terraform (start here)

Scan the container host itself over the `local` channel. Zero setup:

```bash
esp_assessor --channel local -o /tmp/scan.json /opt/prooflayer/esp/linux-ctn-tests/
jq '.replay_hash, .signature.signer_id' /tmp/scan.json
```

Those minimal test policies each exercise one CTN (`sysctl_parameter`,
`linux_kernel_module`, `linux_selinux_state`, `linux_account_audit`) and run
anywhere. For richer Linux output, point it at the bundled Rocky-9 KSI policy set.

To see the same scan flow *through the server* (IA-signed, transparency-logged,
persisted), use the system-ui **Test Scan** page or `POST /api/inventory/test-scan`
(see [../usage/](../usage/README.md)).

---

## Tier 1 — Kubernetes (local, free)

A local kind cluster with a realistic workload set (RBAC, NetworkPolicies,
secrets, StatefulSets, a privileged pod for security checks) is the cheapest way
to get cluster findings — no cloud account. Bring one up with `kind`, then add a
kubeconfig credential and run `POST /api/inventory/discover/k8s/local`, or scan
directly with the bundled Kubernetes policies (CTNs `k8s_*_scoped`). The
manifests + bootstrap for this cluster are part of the
[infrastructure/](infrastructure/README.md) fixtures.

For **network discovery**, a couple of Linux hosts with distinct open-port /
banner fingerprints drive the `discover/network` (CIDR TCP sweep) demo — also in
the infrastructure fixtures. The sweep can only reach hosts the appliance's
**host** can route to (a real gotcha in containers / WSL2); see
[components/network-sweep-discovery.md](../components/network-sweep-discovery.md)
before configuring a `network_target`.

---

## Tier 2 — Cloud Terraform fixtures (billable)

Three bundled fixtures in [infrastructure/](infrastructure/README.md), covering
both the cloud (`local`) channel and the host (`ssh`/`winrm`) channels:

| Fixture | Stands up | Channel(s) | Scan with |
|---|---|---|---|
| [**aws-target**](infrastructure/aws-target/README.md) | Two S3 buckets — one locked-down, one with deliberate drift | `local` | `aws_access_key`/`aws_role` → `aws_s3_bucket` policy |
| [**azure-target**](infrastructure/azure-target/README.md) | An Azure storage account (+ RG) with TLS/HTTPS knobs to fail the policy | `local` | `azure_spn` → `discover/local` + `az_*` policies |
| [**host-targets**](infrastructure/host-targets/README.md) (AWS) | **Ubuntu 22.04 + Rocky 9 + Windows Server 2022** in one VPC; **generates the SSH key + Windows password** | **`ssh`** + **`winrm`** | `ssh_key` + `winrm_password` (generated) → `ubuntu`/`rocky9`/`windows` policies |
| [**azure-host-targets**](infrastructure/azure-host-targets/README.md) (Azure) | **Ubuntu 22.04 + RHEL 9 + Windows Server 2022** in one **resource group**; same generated SSH key + Windows password | **`ssh`** + **`winrm`** | `ssh_key` + `winrm_password` (generated) → `ubuntu`/`rhel9`/`windows` policies |

The **host-targets** pair is the multi-OS discover-and-link story: deploy →
export the generated SSH key → upload it as an `ssh_key` credential → run
discovery → watch the three hosts link under their shared VPC (AWS) or resource
group (Azure) → assign each OS's policies → scan over `ssh`/`winrm`. Pick the
cloud you prefer — Azure's resource-group hierarchy links most cleanly.

General pattern (deploy from the [infrastructure/](infrastructure/README.md) fixtures):

```bash
cd infrastructure/<the fixture you want>
cp terraform.tfvars.example terraform.tfvars   # edit region / allowed_cidr / profile
terraform init
terraform apply
terraform output                          # capture ids / addresses / generated creds
# ... evaluate in Prooflayer ...
terraform destroy                         # tear down — these cost money
```

> **Want more than this?** A multi-tenant landing zone, managed AKS/EKS, or a
> CMMC enclave are **build-your-own** progressions, not bundled fixtures — the
> patterns are in [suggestions.md](suggestions.md). Only the three modules above
> ship as ready-to-`apply` Terraform.

---

## Tier 3 — Seed the UI with sample evidence (no scanning)

To populate the evidence/vulnerability views without running scans, the
container can load the bundled sample seed data (the same catalog + V0 CVE seed
the container loads at first launch). This gives the assessment + VDR pages content to
render. Note these are illustrative rows, **not** signed scans — for a real proof
chain (signature + replay hash + transparency entry), run an actual scan via
Tier 0–2.

---

## Choosing a tier for a demo

| You have… | Use |
|---|---|
| 5 minutes, no cloud | Tier 0 (local scan) → read the envelope + verify the hash |
| A laptop, want K8s findings | Tier 1 (kind) |
| A cloud account, want a cloud-compliance finding | Tier 2 (aws-target / azure-target, `local` channel) |
| Want multi-OS hosts + the `ssh`/`winrm` channels + discover-and-link | Tier 2 (**host-targets** on AWS, or **azure-host-targets** on Azure — Ubuntu / Rocky-or-RHEL 9 / Windows Server) |
| Need the UI to look populated for a screenshot | Tier 3 (sample seed) + one Tier 0 scan for a genuine proof |
