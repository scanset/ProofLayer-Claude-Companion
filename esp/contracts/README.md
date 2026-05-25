# CTN Contract Docs

The authoritative per-CTN reference, bundled into the guide. **One Markdown doc
per CTN**, organized by platform. This is what you read to write an OBJECT and
STATE against a given check — see [../writing-policies.md](../writing-policies.md)
for the workflow and [../language-reference.md](../language-reference.md) for the
catalog with categories.

Each contract doc tells you everything needed to use that CTN:

- **Overview** — what it validates, its platform, and how it collects.
- **Object Fields** — a table of field · type · required · description · example
  (write your `OBJECT` from this).
- **Commands Executed / API calls** — exactly what the collector runs.
- **Sample responses** — the shape of the data your `STATE` compares against.
- **Failure modes** — what produces `Error` vs `Fail`.

To find a CTN: browse the platform folder below, or `grep -ril "<keyword>" .`
from this directory.

## Platforms

| Folder | Coverage |
|---|---|
| [Linux/](Linux/) · [RHEL9/](RHEL9/) · [Ubuntu/](Ubuntu/) | Host-mode Linux CTNs (sysctl, services, packages, files, auditd, SELinux, …) |
| [Windows/](Windows/) | Windows host CTNs (services, registry, security/audit policy, firewall, ACLs) |
| [AWS/](AWS/) | AWS control-plane CTNs (S3, IAM, EC2, security groups, CloudTrail, KMS, … + `_scoped`) |
| [Azure/](Azure/) | Azure control-plane CTNs (storage, Key Vault, NSG, VM, role assignments, Entra, … + `_scoped`) |
| [Kubernetes/](Kubernetes/) | K8s CTNs (`k8s_api_query`, namespace/workload/RBAC/networkpolicy `_scoped`) |
| [M365/](M365/) | Microsoft 365 / Entra CTNs (Graph query, user/group/device/CA/SharePoint `_scoped`) |
| [GitHub/](GitHub/) | SDLC CTNs (org settings, repo metadata, branch protection, workflows) |
| [PostgreSQL/](PostgreSQL/) | `pg_config_param`, `pg_catalog_query` |
| [Apache/](Apache/) · [Network/](Network/) | Apache modules; network probes (TLS/HTTP, network sweep) |

~80 base CTNs, ~200 docs including the `_scoped` injection variants (see
[../injection-and-scoped-injection.md](../injection-and-scoped-injection.md)).

> These docs describe the **checks you compose**; authoring a *new* CTN is engine
> work, out of scope for policy authoring.
