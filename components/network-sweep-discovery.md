# Network-Sweep Discovery — Probe Behavior & Deployment Requirements

How the network-sweep discovery method probes, what it needs from its host
environment, and the failure modes to expect — especially when the appliance
runs in a container. This is the operational deep-dive behind the
[`network_target`](../usage/credentials/network_target.md) credential and the
`discover/network` endpoint; the concept overview is [discovery.md](discovery.md).

> **TL;DR:** the sweep is a **non-root TCP `connect()` scan** (no raw sockets, no
> ICMP, no `nmap`), so privilege/hardening is a non-issue. The only real
> constraint is **reachability**: the sweep can only see hosts its own host can
> route to. Deploy it **on the target network** (the production "central VM
> inside the authorization boundary" model). NAT'd / WSL2 environments often
> can't reach a physical LAN at all.

---

## 1. What it does

`network_sweep` discovers live hosts in an IPv4 CIDR by attempting TCP connects
to a small set of service ports, with an optional SSH/HTTP banner read for OS
hints.

| Property | Value |
|---|---|
| Probe method | full TCP handshake with a connect timeout (connect scan) |
| Default ports | `22` (SSH), `445` (SMB), `3389` (RDP), `80`/`443` (HTTP/S); override via OBJECT `ports` |
| Per-connect timeout | `600 ms` (override via OBJECT `timeout_ms`) |
| Concurrency | 64 parallel workers |
| Host cap | **4096 (a /20)** — larger CIDRs must be split |
| Liveness | a host is "up" if **any** probed port completes a TCP handshake |
| OS hint | optional banner read (≤256 bytes) on open SSH/HTTP |

Inputs come from a [`network_target`](../usage/credentials/network_target.md)
credential and are passed to the collector as env:

```text
NETWORK_CIDR           — target range, e.g. 10.0.0.0/24 (IPv4 only)
NETWORK_EXCLUDE        — optional comma-separated IPs to skip
NETWORK_DEFAULT_ROUTE  — optional gateway IP; probed + tagged role=gateway
```

**Liveness caveat:** a host with every probed port closed (RST) or filtered is
**under-reported** as down. This is a deliberate trade-off — no raw sockets, no
ICMP, no false positives. Widen `ports` if a subnet runs unusual services.

---

## 2. Privilege model — runs unprivileged

By design: *no ICMP* (avoids the raw-socket / `CAP_NET_RAW` requirement), *no
external scanner binary* (no `nmap`), *no crypto* — just plain TCP connects. That
keeps the sweep containerizable, non-root, and FIPS-clean.

Consequences:

- **No `CAP_NET_RAW`, no root.** Runs fine as the appliance's non-root service
  account. (Verified from inside the container: a connect to `8.8.8.8:53` as the
  service account succeeds.)
- **No `nmap` dependency.** Nothing extra to install; not affected by the image
  omitting scanner binaries.
- A SYN-scan or ICMP ping-sweep *would* have required `--cap-add=NET_RAW` (and
  root). This collector deliberately avoids that. **Do not** add `NET_RAW`
  expecting faster scans — the code path won't use it.

---

## 3. Reachability model — the real constraint

A connect scan can only reach hosts the **scanner's host kernel can route to**.
In a container that means whatever the container's network namespace can route
to, which (in default bridge mode) is "anything the Docker host can reach, via
NAT."

Two things follow:

### 3a. Supply the CIDR explicitly — never auto-detect

Inside a container the "local subnet" is the **Docker bridge** (e.g.
`172.17.0.0/16`), not the customer LAN. A sweep that inferred its range from the
local interface would enumerate Docker infrastructure (the gateway, sibling
containers), not real assets. The design avoids this: the operator supplies
`NETWORK_CIDR` on the `network_target` credential — there is no auto-detect
(consistent with the "signals, not triggers" principle). **Always point it at
the real target range.**

### 3b. The host must have a route to the target

- **On a real Linux host that sits on the target subnet** (the production model —
  a central VM inside the authorization boundary): a default **bridge** container
  reaches routable LAN IPs through host NAT. Connect scan works. No special
  Docker flags needed.
- **`--network host`** lets the container share the host's network stack
  directly. Use it only if bridge NAT can't reach the targets *and* the host
  itself can. Trade-offs: it disables `-p` port publishing (the server/nginx
  ports bind directly on the host) and reduces isolation.
- The appliance can never reach a network its **host** can't reach. No container
  flag fixes a missing host route (see §4).

---

## 4. Known environment limitation: NAT'd hosts / WSL2

On a NAT'd developer environment — notably **WSL2** — the appliance host itself
frequently has **no route to the physical LAN**, so no container configuration
can make the sweep reach it.

Observed on a WSL2 dev box trying to reach a LAN target `192.0.2.10`:

```text
# from inside the container (as the service account):
8.8.8.8:53      -> OPEN               # general egress works
192.0.2.10:22   -> No route to host   # LAN target unreachable

# from the WSL2 host itself:
192.0.2.10:22   -> No route to host   # the HOST can't route there either

# the WSL2 host only has a NAT'd interface — no 10.0.0.x route exists:
eth0  172.18.166.84/20   default via 172.18.160.1
```

Because the **host** has no path to `10.0.0.x`, `--network host` and every other
Docker networking mode fail identically. Fixes:

- **For local testing:** enable WSL2 **mirrored networking**
  (`networkingMode=mirrored` in `%UserProfile%\.wslconfig`, Windows 11) so the
  WSL2 VM shares the Windows host's interfaces and LAN routes.
- **For real use:** run the appliance on a host/VM that actually sits inside the
  target subnet. This is the intended deployment shape anyway.

---

## 5. Operational notes

- **Source identity is the host (SNAT).** Scans egress with the Docker host's IP
  via source-NAT, not the container's. Targets and any IDS/IPS attribute the scan
  to the **host**. Make sure the scan is authorized for that source, and expect
  host-IP attribution in target logs.
- **Connection-tracking pressure.** A connect scan opens many short-lived flows.
  A single sweep is capped at **4096 hosts × 5 ports** with 64 workers (bounded),
  but several large sweeps at once can still load the host's `nf_conntrack`
  table. Prefer **/24-sized** ranges; split anything bigger than the /20 cap
  (it's rejected otherwise).
- **Authorization.** A port sweep is active scanning. Only sweep ranges you are
  authorized to assess; unsolicited scanning of third-party networks may violate
  policy or law.

---

## 6. Quick reachability check before sweeping

From the appliance host (or `docker exec` into the container) confirm the target
is routable before configuring a `network_target` credential:

```bash
# Does this host/container have a route + open TCP path to a target?
timeout 4 bash -c 'exec 3<>/dev/tcp/<TARGET_IP>/22' \
  && echo reachable || echo "no route / filtered"
```

If that fails from the **host**, the sweep will find nothing regardless of
container settings — fix host routing (or relocate the appliance) first.

---

Related: [discovery.md](discovery.md) (discovery overview),
[../usage/credentials/network_target.md](../usage/credentials/network_target.md)
(the credential), [channels.md](channels.md), and the network-sweep targets in
[../test_fixtures/](../test_fixtures/README.md).
