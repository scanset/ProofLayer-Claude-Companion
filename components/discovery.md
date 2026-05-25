# Discovery

**Status: partial — discovery endpoints exist; "discovery-as-policy" is the design target.**

## What it is

Discovery turns **one credential into a list of assets** — the time-to-value
step that means you don't hand-enter 200 assets. Add a credential, run
discovery, and the asset inventory fills with what that credential can see, ready
to link policies to.

```
add credential → discovery enumerates assets via that credential
              → asset rows created → link policies → first scans → first findings
```

What a credential discovers:

| Credential | Discovers (→ asset types) |
|---|---|
| `aws_access_key` / `aws_role` | EC2, S3, IAM, EKS, RDS… → `ec2_instance`, `aws_account`, … |
| `azure_spn` | ARM resources scoped to the SPN's grants → `azure_vm`, `azure_subscription`, … |
| kubeconfig / SA token | namespaces, workloads, RBAC, network policies |
| M365 / Graph | users, groups, devices, conditional-access, SharePoint |

## The endpoints (alpha)

`/api/inventory/discover/*`: `local` (SSH/local inventory), `m365`,
`m365_purview`, `m365_pwsh`, `k8s/local`, `k8s/aks`, `k8s/eks`, `network` (CIDR
TCP sweep). Each returns discovered assets (with provider metadata + graph
`parents`), which then feed [injection](../esp/injection-and-scoped-injection.md) and
scanning.

> The `network` sweep has its own operational deep-dive — probe behavior,
> unprivileged connect-scan model, and the reachability requirement (it can only
> see what the appliance's host can route to, a real gotcha in containers/WSL2):
> [network-sweep-discovery.md](network-sweep-discovery.md).

## Discovery-as-policy (the design direction)

The architectural target is that discovery is a
**special ESP policy**, not bespoke per-provider code: a policy with
`META.assessment_method = DISCOVERY` that references a **list-mode CTN**
(`az_resource_list`, `aws_*_list`, …). When such a policy completes, the engine
routes its enumerated records to the **asset registry** instead of findings, via
a per-CTN rule that turns each record into an asset.

The payoff: new providers are added by *authoring a discovery policy + a
list-mode contract*, not by changing the server — and discovery is itself
**attestable** ("on date D, credential C enumerated assets X, Y, Z" is signed,
logged evidence). The single language change this requires (`DISCOVERY` as an
`assessment_method` value) is upstream-pending on the ESP engine; today's
discover endpoints are the interim implementation.

## Deliberate, not magic

Discovery is signals-not-triggers by design: the operator picks the OS profile
(no auto-detect); a `k8s_present` flag is surfaced but doesn't auto-run K8s
discovery. Explicit beats magic — discovery enumerates when you ask it to.

See [usage/](../usage/README.md) to run it and
[inventory.md](inventory.md) for where the results land.
