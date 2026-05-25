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

## Tier 2 — Cloud landing zones (Terraform, billable)

The marquee fixture is a **multi-tenant landing zone** — a hub + three tenant
spokes per cloud, with **intentional drift** (TLS 1.0 storage, public buckets,
disabled diagnostics) so the scanner produces real findings across tenants.

| Fixture | Stands up | Scan with |
|---|---|---|
| **Azure landing zone** | Hub VNet, Log Analytics, policy assignments, 3 tenant spokes (storage/KV/NSG, with drift) | `azure_spn` cred → `discover/local` + `az_*` policies |
| **AWS landing zone** | Hub VPC, central S3 log archive, Access Analyzer, 3 tenant spokes (S3/KMS/IAM/EC2, with drift) | `aws_access_key`/`aws_role` cred → `aws_*` policies |
| **AKS cluster** | Azure Kubernetes Service + RBAC | `azure_spn` → `discover/k8s/aks` |
| **EKS cluster** | AWS EKS + RBAC | aws cred → `discover/k8s/eks` |
| **Single Linux VM** | One VM as an SSH/Bastion target | `ssh_key` → `--channel ssh` / `az-bastion` |
| **CMMC enclave** | Staged M365 + Azure baseline + Intune + Purview enclave (multi-step) | `azure_spn` / M365 → `discover/m365*` |

General pattern (deploy from the [infrastructure/](infrastructure/README.md) fixtures):

```bash
cd <the fixture you want>
cp terraform.tfvars.example terraform.tfvars   # where provided; edit subscription/region/keys
terraform init
terraform plan
terraform apply
terraform output                          # capture ids/ARNs to register as assets/creds
# ... evaluate in Prooflayer ...
terraform destroy                         # tear down — these cost money
```

Each fixture documents its variables, the drift it plants, and what the scanner
should flag. The CMMC enclave is multi-stage — follow its own ordered README.

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
| A cloud account, want a real cross-tenant compliance story | Tier 2 (landing zone) |
| Need the UI to look populated for a screenshot | Tier 3 (sample seed) + one Tier 0 scan for a genuine proof |
