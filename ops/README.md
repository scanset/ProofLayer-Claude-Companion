# Operations — Running the Container

Day-to-day operation of the Prooflayer alpha container once it's running:
processes, the PKI on disk, logs, backup, and troubleshooting. This is the
**host/container** layer — for tasks done *inside* the product (users, keys,
schedules, frameworks) see [admin/](../admin/README.md); for pull-and-run
bring-up see [setup/](../setup/README.md).

> The container is self-contained and self-provisioning. Its internal datastore
> is a **sealed implementation detail** — it comes up automatically, isn't
> reachable from the host, and isn't something an operator manages. None of the
> tasks below require touching it.

---

## 1. Processes

A supervisor runs the long-lived processes inside the container:

| Process | What | Health signal |
|---|---|---|
| internal datastore | The sealed application + transparency store, loopback-only (not exposed) | comes up automatically before the server |
| `prooflayer-2` | The server, on loopback `127.0.0.1:3000` | `GET /health` |
| `nginx` | reverse proxy + static UI serving on **`:80`** (operator) and **`:8081`** (CMR read API); plain HTTP, no TLS | `nginx -t` |

The server won't accept traffic until its datastore is ready; nginx 502s until
the server is listening on loopback `:3000`.

```bash
# From the host
curl -s http://localhost:8080/health
# Inside the container
curl -s http://127.0.0.1:3000/health
nginx -t && supervisorctl status
```

The server's startup log prints the PKI load, the scanner identity it minted
(`esp://prooflayer/<deployment_name>/scanner`), and the router binds.

---

## 2. PKI on disk

Generated at first launch into `/opt/prooflayer/pki/`:

```
pki/
├── root-ca/        root-ca.crt (10y, self-signed)   + root-ca.key  ← keep offline in prod
├── prooflayer-ia/  ia.crt (1y, pathlen:1) + ia.key  + chain.crt
└── trust-bundle/   root-ca.crt / root-ca.pem        ← safe to distribute
```

The IA is loaded at server start; the segment CA and the log-signing +
scanner-identity certs are minted **in memory** at startup — they are not on
disk. (nginx serves plain HTTP in the eval container, so no TLS cert is
presented to the browser; the PKI here exists to sign scan envelopes and the
transparency log, not to terminate TLS.) The *concept* — issuance chain,
scanner identity, transparency anchoring — is in
[components/pki-and-identity.md](../components/pki-and-identity.md).

```bash
openssl x509 -in /opt/prooflayer/pki/prooflayer-ia/ia.crt -noout -subject -dates -ext basicConstraints
```

---

## 3. Logs

The server uses `tracing`. `RUST_LOG=info` by default; bump a subsystem with
e.g. `RUST_LOG=prooflayer_2::evidence=debug`. With the supervisor wired to
stdout, `docker logs prooflayer` aggregates the processes; otherwise:

```bash
docker logs -f prooflayer
tail -f /var/log/nginx/system-error.log    # inside the container
```

---

## 4. Backup & restore

State that matters lives on the named volume (`/var/lib/prooflayer` in the
[setup/](../setup/README.md) run command): the datastore, the PKI, and the
session secrets. **Backup = snapshot the volume; restore = mount it back.** No
store-level commands are involved — the datastore is opaque.

```bash
# Backup (container stopped or quiesced)
docker run --rm -v prooflayer-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/prooflayer-data.tgz -C /data .

# Restore into a fresh volume
docker run --rm -v prooflayer-data:/data -v "$PWD":/backup alpine \
  tar xzf /backup/prooflayer-data.tgz -C /data
```

Persisting the volume across restarts keeps your evidence, your transparency
log, and your sessions. Dropping the volume gives you a clean instance.

---

## 5. Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Server won't start | datastore not ready yet, or a missing secret | wait for first-launch provisioning to finish; check `docker logs` |
| nginx 502 | server not listening on `:3000` | `curl 127.0.0.1:3000/health` inside the container |
| `unknown variant <kind>` at scan time | server and scanner built from mismatched versions | shouldn't happen in the shipped image; re-pull a clean image |
| Scan ingest silently dropped | an ingest-time validation/integrity error | check the server log around the ingest; compare the transparency entry count |
| Empty transparency page | no scans run yet, or an ingest rolled back | run a test-scan; check the server log |

One ingest trap worth knowing (it bit before): the ESP `Outcome` enum has a 4th
variant `unknown`; ingest must permit it or a whole-scan ingest rolls back and
the transparency page silently loses that envelope's signing activity. Fixed
in-tree — don't "fix" it by remapping outcomes (that breaks replay-hash
integrity).

---

## 6. What not to touch

- **Replay-hash inputs / outcome mapping** — changing what feeds the hash breaks
  fleet dedup and replay verification.
- **The append-only protection** on the transparency log — that's the point.
- **The internal datastore** — it's sealed by design; the supported way to reset
  state is a fresh volume, not poking at the store.

---

## 7. Account recovery

The alpha is a single super-admin model with a fixed default login
(`super-admin` / `prooflayer`) and no password change. If you're locked out
(e.g. a stale session or a secret problem), the supported recovery is to
**redeploy on a fresh volume** — the default login comes back on a clean start.
This discards local state (evidence, inventory, transparency log), so back up
the volume first (§4) if you want to keep it.
