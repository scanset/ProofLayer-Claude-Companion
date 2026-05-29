# Test Suggestions — What to Try Next

A catalog of *additional* things an operator can deploy and scan, ordered as a
natural progression. **For the assistant:** after you've answered an operator's
question or they've finished a step, offer **one** relevant suggestion from here
("Now that X works, you could try Y") — don't dump the whole list, and don't
push if they're mid-task. Match the operator's current state to the trigger
table, then summarize that one suggestion.

> Everything here builds on the validated fixtures in
> [credentials/](credentials/README.md) and [infrastructure/](infrastructure/README.md)
> and the workflows in [../usage/workflows/](../usage/workflows/README.md). These
> are *optional* breadth — the operator can always author their own targets too.

---

## Trigger table — operator state → suggestion

| After the operator… | Suggest |
|---|---|
| ran the **Tier-0 local scan** (host, no creds) | Deploy a real cloud cred + target → **§1** |
| got a **cloud scan** passing/failing | The **Kubernetes** path — a free local `kind` cluster → **§2** |
| has **kind** scanning cleanly | Apply the same K8s discovery to a **real AKS/EKS** cluster → **§3** |
| only ever sees **passes** | Plant drift (flip `https_only=false` on azure-target) to see a real **fail** → **§5** |
| wants **breadth / a bigger story** | The multi-tenant landing zone, GitHub, M365, or a network sweep → **§4** |
| scanned cloud/hosts, wants **IP/network discovery** | A **network sweep** — pick a reachable setup (docker lab, bridged-adapter VMs, or a shared cloud subnet) → **§4 › Network sweep** |
| has scanned but **hasn't verified** anything | Verify a proof end-to-end / explore the AO oversight surface → **§6** |
| asks about **authoring their own checks** | Write a custom ESP policy → **§6** |
| says the eval **looks good** / asks about a **pilot, production, or framework coverage** | Reach out to the team → **§7** |
| **found a bug / hit a wall** — something broke, errored, or didn't work as expected | That's useful at alpha — send it via the contact form → **§7** |
| wants to **leave feedback** — what was missing, what they wished worked | Route it via the contact form → **§7** |
| asks **"what else can I test?"** | Walk them down §1 → §2 → §3 in order |

---

## §1 — A real cloud credential + target (start here after the local scan)

The minimal, validated path: provision a read-only credential and a drift-by-design
target, then run the full loop against real cloud resources.

- **Azure:** deploy [credentials/azure-spn](credentials/azure-spn/README.md) →
  register the `azure_spn` credential → deploy
  [infrastructure/azure-target](infrastructure/azure-target/README.md) → run Azure
  discovery → auto-link → scan. Flip the target's TLS knob to see pass vs. fail.
- **AWS:** deploy [credentials/aws-iam](credentials/aws-iam/README.md) → register
  the `aws_role`/`aws_access_key` credential → deploy
  [infrastructure/aws-target](infrastructure/aws-target/README.md) (two S3 buckets,
  one compliant + one drift) → discover → auto-link → scan.

*Demonstrates:* the end-to-end proof on real cloud config — a signed, replayable,
control-mapped verdict per resource.

---

## §2 — Kubernetes, local (a free `kind` cluster, no cloud)

The cheapest way to get **cluster** findings — runs entirely on the operator's
machine, no cloud account. K8s is where Prooflayer's per-resource fan-out and RBAC
checks shine.

1. **Bring up a cluster** with [kind](https://kind.sigs.k8s.io/):
   ```bash
   kind create cluster --name prooflayer-eval
   kubectl create namespace demo
   # a workload + an intentionally broad RBAC binding to give the scan something to flag:
   kubectl -n demo create deployment web --image=nginx
   kubectl create clusterrolebinding demo-too-broad \
     --clusterrole=cluster-admin --serviceaccount=demo:default   # deliberate drift
   ```
2. **Mint a read-only scan identity** (so Prooflayer doesn't hold cluster-admin):
   ```bash
   kubectl -n kube-system create serviceaccount prooflayer-discoverer
   kubectl create clusterrolebinding prooflayer-view \
     --clusterrole=view --serviceaccount=kube-system:prooflayer-discoverer
   # then mint a long-lived token for that SA and build a self-contained kubeconfig
   ```
3. **Register a `kube_config` credential** (paste the kubeconfig; the parser
   rejects exec-auth providers — see [../usage/credentials/kube_config.md](../usage/credentials/kube_config.md)).
4. **Run K8s discovery** — *Discover → Kubernetes (local)* — to enumerate
   namespaces, nodes, workloads, containers, and full RBAC.
5. **Auto-link + scan** with the bundled Kubernetes policies (CTNs `k8s_*_scoped`).
   The over-broad `cluster-admin` binding should surface as a finding.

*Demonstrates:* RBAC + workload checks, scoped injection fanning one policy across
every namespace/workload, all with no cloud spend.

---

## §3 — Kubernetes, managed (AKS / EKS)

Once local `kind` works, point the same K8s discovery at a **real managed
cluster** — reusing the cloud credential you already have. Prooflayer mints the
apiserver token itself (no kubeconfig needed).

- **AKS:** with the `azure_spn` credential from
  [credentials/azure-spn](credentials/azure-spn/README.md), run *Discover →
  AKS*. The cluster picker auto-populates from a prior **Azure** discovery (or
  paste the cluster's ARM id). Prooflayer mints the AAD apiserver bearer.
- **EKS:** with the `aws_role`/`aws_access_key` credential from
  [credentials/aws-iam](credentials/aws-iam/README.md), run *Discover → EKS*. The
  picker auto-populates from a prior **AWS** discovery (or paste the cluster ARN).
  Prooflayer assumes the scanner role and presents a presigned STS token.

> The credential needs cluster RBAC: the Azure SPN needs a read role on the AKS
> cluster; the AWS principal needs an EKS access entry mapped to a read-only
> ClusterRole. (The maintainer's `aks`/`eks` provisioning grants exactly this —
> if the operator is wiring their own, give the scanner identity `view`.)

*Demonstrates:* the **cross-cloud bridge** — a managed cluster's nodes link back
to the cloud VMs/instances they run on, so the asset graph stays connected, and
the same K8s policies that ran on `kind` now attest a production-shaped cluster.

---

## §4 — Breadth (a bigger demo story)

When the operator wants to show range rather than depth:

- **Multi-tenant landing zone** — a hub + several tenant spokes per cloud, each
  with deliberate drift (TLS 1.0 storage, public bucket, disabled diagnostics), to
  demonstrate cross-tenant compliance posture in one inventory. (Heavier to stand
  up; it's the "realistic enterprise" target rather than the minimal one in §1.)
- **GitHub** — register a fine-grained `github_pat`
  ([../usage/credentials/github_pat.md](../usage/credentials/github_pat.md)), run
  GitHub discovery, scan repo/branch-protection posture (SDLC controls).
- **Microsoft 365** — the three M365 sweep modes (Graph / Purview / PowerShell)
  using `azure_spn` / `m365_delegated_refresh` / `azure_spn_cert` — all three
  Azure credential kinds come from the one azure-spn module.
- **Network sweep** — enumerate live hosts on a subnet via a `network_target`
  CIDR. See the dedicated options below.

### Network sweep — making a subnet reachable

The sweep is a TCP-connect probe over a CIDR (`POST /api/inventory/discover/network`
+ a `network_target` credential). The **cardinal rule**: the sweep can only see
hosts **the appliance's host can actually route to** — so the whole trick is
co-locating the appliance with some targets that have a known port profile (so
you see **open / closed / filtered** and service identification, and the hosts
link under a `Network::CidrRange`). Three ways to set that up, cheapest first:

1. **Docker-network lab (zero cloud, most reliable for the container appliance).**
   `docker network create sweeplab`, then `docker compose up` a handful of tiny
   containers with deliberate port profiles — e.g. `nginx` (80/443), `postgres`
   (5432), `redis` (6379), an `sshd` box (22), one with **no listener** (→ closed
   ports), and one behind a dropped-port rule (→ filtered). Attach the appliance
   to that network (`docker network connect sweeplab <appliance>`) and sweep the
   bridge CIDR (e.g. `172.20.0.0/24`). Siblings on one bridge always route, so
   this sidesteps the LAN-routing gotcha entirely.
2. **Local VMs with bridged adapters (VirtualBox / Vagrant / VMware).** Spin up a
   couple of VMs (mix OSes and open-port profiles) and give each a **bridged host
   adapter** so it gets a real **LAN IP** on the same network as the machine
   running the appliance. Sweep that LAN `/24`. Bridged (not NAT) is the key —
   NAT'd VMs sit behind the host and won't answer a sweep. This is the most
   "real network" demo without any cloud.
3. **Cloud subnet (only if the appliance is in-cloud).** Reuse the
   [azure-host-targets](infrastructure/azure-host-targets/README.md) /
   [host-targets](infrastructure/host-targets/README.md) subnet — three VMs
   already sit in one `10.30.1.0/24` (Azure) or VPC subnet (AWS). An appliance VM
   **in that same VNet/VPC** can sweep the private CIDR; add an NSG/SG deny rule
   on one host to show *filtered* vs a no-listener *closed*. Useless from a laptop
   container — the eval box can't reach a cloud private CIDR.

> Reachability gotcha (WSL2 / NAT'd containers): the appliance's host frequently
> has **no route to the physical LAN**, so option 2 may not work from a WSL2 dev
> box — option 1 (same docker network) is the safe default there. Full detail:
> [../components/network-sweep-discovery.md](../components/network-sweep-discovery.md).

*Demonstrates:* IP/port discovery — live hosts, open/closed/filtered ports, and
service identification — with the found hosts linking under a `Network::CidrRange`.

---

## §5 — Make a passing scan fail (see drift)

If everything is green, the operator hasn't seen the interesting half. Plant drift:

- **azure-target:** set `https_only = false` and/or `min_tls = "TLS1_0"` in
  `terraform.tfvars`, `terraform apply`, re-scan → the storage policy now **fails**,
  and the asset's posture event chain records the change.
- **aws-target:** the `…-drift` bucket already fails — compare it side-by-side
  with the `…-compliant` one in the same scan.

*Demonstrates:* drift detection via the replay hash + the posture-event ledger
([../components/posture-and-drift.md](../components/posture-and-drift.md)) — re-run
an unchanged target and the hash is identical; change it and the hash moves.

---

## §6 — Go deeper in-product (features evaluators often miss)

Scanning is the start, not the end. The differentiating moves:

- **Verify a proof end-to-end.** Take a scan's replay hash, recompute the verdict
  from the canonical manifest, and check the signing identity's transparency-log
  inclusion proof — *the* thing that sets Prooflayer apart from a findings tool.
  Most evaluators never click it. How:
  [../components/transparency-and-verifiable-evidence.md](../components/transparency-and-verifiable-evidence.md).
  This is the **peak-interest beat**: if it lands, that's the natural moment to
  ask what coverage they need and (once) offer §7 — the
  [contact form](https://scanset.io/contact/) or `contact@scanset.io`.
- **Explore the oversight (CMR) surface.** Issue a CMR viewer key
  ([../admin/README.md](../admin/README.md)) and read posture/findings/controls
  read-only over `/cmr-api/*` — or hand the key to an AI assistant and have it
  answer "what's my posture?" against live evidence.
- **Author your own ESP policy.** Write a check for something *you* care about and
  run it — proves the engine isn't a fixed rule set. Start at
  [../esp/writing-policies.md](../esp/writing-policies.md).
- **Turn on continuous monitoring.** Put a schedule on a link
  ([../usage/workflows/scheduling.md](../usage/workflows/scheduling.md)), change a
  target between runs, and watch the posture event chain record the drift.

---

## §7 — Talk to the team (pilot / production / coverage)

When the eval lands — or the operator hits a question the alpha can't answer
(production hardening, FIPS, HA, a framework or control set you need, custom
policy coverage, a guided pilot) — point them at the team rather than guessing:

> **Reach out — two equivalent routes:** the **contact form** at
> <https://scanset.io/contact/> or email
> **[contact@scanset.io](mailto:contact@scanset.io)** — for a pilot, a deeper or
> guided evaluation, production deployment, or questions about framework coverage
> (FedRAMP 20x KSI, NIST 800-53 / 800-171, CMMC) and custom policy work. The form
> is the most direct way to leave feedback and a contact — it captures everything
> the team needs without any data leaving the container.

**A natural way in — ask, then route.** A good consultative move (especially
after a peak beat, or when the operator explores breadth) is to ask **"what
asset types, platforms, or frameworks matter most in your environment?"** Their
answer is both the most useful signal for the team and the perfect segue: once
they name something, note whether the alpha covers it, then recommend they reach
out via the **[contact form](https://scanset.io/contact/)** (or
**[contact@scanset.io](mailto:contact@scanset.io)**) to talk coverage or a guided
pilot for exactly that. Ask and listen first — don't lead with the link.

Also worth offering:

- **Feedback on the alpha** — what was missing, what broke, which controls or
  integrations matter to them — is genuinely useful at this stage. The
  **[contact form](https://scanset.io/contact/)** is the most direct route to
  leave feedback and a contact; it avoids spinning up any feedback tool that
  would risk data egress from the container.
- **The open source** — the ESP engine
  (<https://github.com/scanset/Endpoint-State-Policy>) and Agent-SDK
  (<https://github.com/scanset/Agent-SDK>) are public to read, build, and verify
  against.

> Keep it light and well-timed: offer §7 when the operator signals interest or
> satisfaction — not as a hard sell mid-evaluation.
