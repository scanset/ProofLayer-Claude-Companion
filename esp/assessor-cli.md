# The `assessor` CLI

`esp_assessor` is the standalone scanner — the same engine as the server,
producing **byte-identical envelopes**. Use it to debug policies, run
ad-hoc/CI/air-gapped scans, and validate a policy before linking it to assets.

> **Testing ESP open-source.** The scanner is the open-source **ESP engine** —
> compiler + execution engine + CLI. To test policies independently of the
> Prooflayer container (locally, in CI, on a workstation), build it from
> <https://github.com/CurtisDSlone/Endpoint-State-Policy>. The **Agent-SDK**
> (<https://github.com/CurtisDSlone/Agent-SDK>) is the public repo for developing CTN
> contracts and testing ESP policies against the engine.

> Flags below are the scanner's actual CLI surface. **There is no
> `--format` flag** — console output is human-readable; `-o` writes the machine
> envelope (the agent always emits the full shape; narrower views are a consumer
> concern — see [the-envelope.md](the-envelope.md) §6).

---

## 1. Shape

```
esp_assessor [FLAGS] <policy.esp | directory-of-policies>
```

The positional argument is one `.esp` file or a directory (scanned recursively).
A directory still yields **one** envelope with many policies — single-envelope
design.

| Flag | Meaning |
|---|---|
| `--channel <kind>` | `local` (default) · `ssh` · `aws-ssm` · `az-bastion` · `winrm` |
| `-o, --output <path>` | write the JSON envelope to a file |
| `--bundle-output <path>` | write a scan bundle (dispatcher/subprocess mode) |
| `--config-json <path>` | read the entire scan configuration from a JSON file (mutually exclusive with `--channel` + per-channel flags) |
| `-q, --quiet` | suppress console output |

**Exit codes:** `0` all passed · `1` one or more failed · `2` execution error.

`--channel` says *how to reach the target*; it's orthogonal to the CTNs a policy
uses (concept in [how-esp-works.md](how-esp-works.md) §2 and
[../components/channels.md](../components/channels.md)).

---

## 2. Per-channel flags & examples

### `local` (default — scans the host the CLI runs on; also cloud control planes via the provider CLI)
```bash
esp_assessor --channel local -o /tmp/out.json /opt/prooflayer/esp/R9/
```

### `ssh` (agentless remote Linux — needs `--ssh-host`, `--ssh-user`, `--ssh-key`)
```bash
esp_assessor --channel ssh \
  --ssh-host 10.0.0.5 --ssh-user azureuser --ssh-key ~/.ssh/id_ed25519 \
  -o remote.json /opt/prooflayer/esp/R9/
```
Optional: `--ssh-port` (22), `--ssh-connect-timeout` (10s), `--ssh-known-hosts`,
`--ssh-insecure-host-key`.

### `aws-ssm` (EC2 via Systems Manager, no inbound SSH — needs `--aws-region`, `--aws-instance-id`)
```bash
esp_assessor --channel aws-ssm \
  --aws-region us-east-1 --aws-instance-id i-0abc123 \
  -o aws.json /opt/prooflayer/esp/R9/
```
Optional: `--aws-profile`, `--aws-binary`, `--aws-use-fips` (default on) /
`--aws-no-fips`, `--aws-poll-ms` (750).

### `az-bastion` (Azure VM behind Bastion — tunnel + inner SSH)
```bash
esp_assessor --channel az-bastion \
  --az-subscription <sub> --az-resource-group <rg> --az-bastion-name <bastion> \
  --az-target-resource-id <vm-arm-id> --az-local-port 50022 \
  --ssh-user azureuser --ssh-key ~/.ssh/id_ed25519 \
  -o bastion.json /opt/prooflayer/esp/R9/
```
Optional: `--az-remote-port` (22), `--az-binary`, `--az-tunnel-timeout` (15s),
plus the SSH inner-session flags. (`--ssh-host`/`--ssh-port` are *not* valid
here — the channel forces `127.0.0.1:<az-local-port>`.)

### `winrm` (Windows over HTTPS — password via env, never argv)
```bash
SCANSET_WINRM_PW=... esp_assessor --channel winrm \
  --winrm-host win01 --winrm-user scanner --winrm-password-env SCANSET_WINRM_PW \
  --winrm-ca-bundle /etc/winrm-ca.pem \
  -o win.json /opt/prooflayer/esp/windows/
```
Optional: `--winrm-port` (5986), `--winrm-request-timeout` (30s),
`--winrm-allow-self-signed` (dev only), `--winrm-auth` (`basic` default | `kerberos`),
`--winrm-kerberos-spn`.

---

## 3. When to use the CLI vs the server

| Use the **CLI** for | Use the **server** for |
|---|---|
| Debugging a policy you're writing (`--channel local`) | Scheduled / fleet scanning |
| CI/CD or air-gapped one-shot scans | Signed-by-IA + transparency-logged + persisted evidence |
| Confirming a clean compile + expected outcome | Injection/auto-attach across many assets |

Both produce identical envelopes; the difference is what happens *after* the
scan. The server signs with its scanner identity, appends to the transparency
log, and persists to evidence — see
[../components/evidence-and-ingest.md](../components/evidence-and-ingest.md). For
the in-product scan flow, see [../usage/README.md](../usage/README.md).

> Secrets never go on `argv` (world-readable via `/proc`): SSH uses a key file,
> WinRM/cloud secrets come from env vars. Keep it that way.
