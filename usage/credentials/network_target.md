# `network_target`

## What it represents

A **scan-target spec, not a secret**. `network_target` is a CIDR range to probe
for live hosts — modeled as a "credential" only so it flows through the same
discovery dispatcher as the real credential kinds. It carries no auth material.
The Prooflayer VM must have a network route to the CIDR.

It is one of two no-secret pseudo-credentials (the other is [`local`](local.md)).

## Payload fields

| Field           | Required | Description                                                        |
|---              |---       |---                                                                 |
| `cidr`          | yes      | IPv4 CIDR to sweep, e.g. `10.0.0.0/24`.                            |
| `exclusions`    | no       | Individual IPs to skip during the sweep.                           |
| `default_route` | no       | Gateway IP — probed and tagged `role=gateway`.                     |

## What it drives

Network discovery — `POST /api/inventory/discover/network` — a TCP sweep of the
CIDR that registers a `CidrRange` asset plus a `Local::Host` per live host found.
The probe behavior, privilege model, and the **reachability requirement** (the
appliance can only sweep what its host can route to — important in containers /
WSL2) are in
[components/network-sweep-discovery.md](../../components/network-sweep-discovery.md).
See also [components/discovery.md](../../components/discovery.md) and the
network-sweep fixtures in [test_fixtures/](../../test_fixtures/README.md).

## Adding one

System-UI → **Admin** → **Credentials** → **Add credential** → kind
`network_target`; enter the CIDR (and optional exclusions / gateway). No secret
to rotate — it's a target definition. Storage model is the same role-scoped
plaintext-at-rest store as every other credential (see the [index](README.md));
there's nothing sensitive in it.

## Security model

No secret material. The only sensitivity is operational — the CIDR reveals
internal addressing — so it's still admin-gated to write and produces a
transparency-log entry like any credential operation.
