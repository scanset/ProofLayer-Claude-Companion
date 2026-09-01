# Setup — Running the Prooflayer Alpha Container

The alpha ships as a single **all-in-one image** you pull and run. There is
nothing to build, nothing to configure, and no database to set up — the
container provisions everything it needs on first launch and **just works**.

```bash
docker pull curtisdslone/prooflayer-alpha-v0_1:0.1-alpha   # exact ref provided with the eval
```

Inside the image: the Prooflayer server, nginx (reverse proxy + static UI),
the `esp_assessor` scanner CLI, an internal datastore, and the seeded ESP
policy tree and CTN contract docs — all on Rocky Linux 9. The internal datastore
is a sealed implementation detail; you never touch it.

---

## 1. Ports

The image exposes **two** ports — both plain HTTP (TLS is omitted in the local
eval image), both served by nginx:

| Port (in container) | Serves | Notes |
|---|---|---|
| **`80`** | the **operator** surface — the system-ui app + `/api`, `/cmr-api`, `/verify`, `/health` | This is the console an evaluator uses. |
| **`8081`** | the **CMR read API only** — `/cmr-api`, `/health`; everything else returns `404` | A dedicated, key-gated surface for external consumers (AO / SIEM / an AI assistant). |

Everything else stays **inside** the container and is not reachable from the
host — including the internal datastore.

---

## 2. Running it

```bash
# -p 8080:80   → operator UI + API  (http://localhost:8080/)
# -p 9090:8081 → CMR read API       (http://localhost:9090/cmr-api/...)
docker run -d --name prooflayer \
  -p 8080:80 \
  -p 9090:8081 \
  -v prooflayer-data:/var/lib/prooflayer \
  curtisdslone/prooflayer-alpha-v0_1:0.1-alpha
```

That's the whole bring-up. On first launch the container generates its own PKI,
its own secrets, seeds its datastore and the control catalog, mints the
in-process scanner identity, and starts the server behind nginx — all
automatically and idempotently. A restart reuses what's already there.

The named volume persists state (your evidence, transparency log, PKI, and
sessions) across restarts. Omit it for a throwaway run; the next start comes up
clean. Publish `8081` to consumers and keep the operator port internal if you
want the two surfaces segmented.

> Per-container secrets are generated fresh at first launch. Two containers from
> the same image do not share keys. These are eval-grade defaults — never reuse
> this image, or anything it generates, anywhere real.

---

## 3. Logging in (first run)

1. Browse to `http://localhost:8080/`. The eval container serves plain HTTP
   (no TLS), so there's no certificate warning.
2. **Accept the EULA.** A one-time end-user license agreement modal gates the
   sign-in screen; click **I Agree** to proceed. Acceptance is stored
   per-version in the browser, so you won't be re-prompted unless the terms
   change.
3. Log in:
   - **Username:** `super-admin`
   - **Password:** `prooflayer`

The alpha uses a **single super-admin model**: the seeded credentials just
work. There is no password-change prompt, no operational-user creation, and no
bootstrap-finalize ceremony.

> Locked out (e.g. a session/secret problem)? The simplest recovery in the alpha
> is to redeploy on a fresh volume — the default `super-admin` / `prooflayer`
> login comes back on a clean start. See [ops/](../ops/README.md#7-account-recovery).

---

## 4. Smoke test the running container

```bash
# Server health (through nginx)
curl http://localhost:8080/health

# Log in and capture a JWT
curl -X POST http://localhost:8080/system-ui/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"super-admin","password":"prooflayer"}'

# Run a local scan inside the container (no creds needed) and read the proof
docker exec prooflayer esp_assessor --channel local -o /tmp/scan.json \
  /opt/prooflayer/esp/linux-ctn-tests/
docker exec prooflayer jq '.replay_hash, .signature.signer_id, (.observations|length)' /tmp/scan.json
```

If the health check is `ok`, login returns a token, and the local scan emits a
`replay_hash` + signature, the container is good. Next:
[usage/](../usage/README.md) for the end-to-end product walkthrough, or
[test_fixtures/](../test_fixtures/README.md) to deploy real scan targets.

---

## 5. What the container manages for you

You don't configure any of this — it's listed so you know what's happening
behind the "just works":

| Concern | Handled at first launch |
|---|---|
| **PKI** | Self-signed root + issuing authority generated on disk; the in-memory scanner and log-signing identities are minted from it. Conceptual detail: [components/pki-and-identity.md](../components/pki-and-identity.md). |
| **Secrets** | Session-signing secrets generated per-container and persisted to the volume. |
| **Datastore** | The internal store is provisioned and seeded automatically — schema, the control catalog (FedRAMP 20x KSI, NIST 800-53, NIST 800-171), and a starter vulnerability catalog. Sealed; not operator-facing. |
| **Scanner identity** | An in-process workload identity (`esp://prooflayer/<deployment>/scanner`) is minted and logged to the transparency log. |
| **ESP policies + contracts** | The policy tree and CTN contract docs are baked into the image and loaded at start. |

For host/container lifecycle once it's running (processes, logs, backup,
troubleshooting) see [ops/](../ops/README.md).
