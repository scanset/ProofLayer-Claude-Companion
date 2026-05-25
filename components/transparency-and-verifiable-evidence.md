# Transparency Log & Verifiable Evidence

**Status:** reference — how a Prooflayer attestation is made reproducible, and
how far toward *independently verifiable* it is today.
**Audience:** anyone evaluating the proof guarantees (AO, assessor, SIEM/SOAR
integrator, diligence reviewer) or implementing a verifier.

Companion: [replay-hash-canonical-spec.md](replay-hash-canonical-spec.md) — the
byte-exact hash contract. **This page is the *story*; that page is the *math*.**
The concept overview is [transparency-log.md](transparency-log.md).

---

## 1. TL;DR — what we can honestly claim

Prooflayer does not just emit a finding; it emits a **proof of a verdict** — a
fingerprint of *intent + execution + outcome* that a third party can recompute.

Two claims, not the same:

- ✅ **Reproducible (true today).** Every input needed to recompute a verdict's
  `replay_hash` is exposed over the read-only API: the readable policy, the
  reconstructed canonical manifest, the stored per-object leaves, the signature,
  the signer's public key + certificate chain, and a transparency-log inclusion
  proof. Given the published canonical spec, the hash can be reproduced from
  these inputs.
- 🔶 **Independently verifiable (in progress).** "Independent" means *the consumer
  computes it themselves and roots every anchor in something we do not control.*
  Three things still stand between reproducible and independently verifiable —
  see [§6](#6-the-honest-claim-hierarchy). Until then the accurate phrasing is
  *"reproducible from exposed inputs, verifiable against a trusted root."*

> Do not write "independently verifiable" in customer-facing material yet. Write
> "reproducible" or "verifiable against a trusted root." See §6.

---

## 2. The three artifacts of a proof

A single attestation binds three independent things. Each answers a different
question and rests on a different trust basis.

| Artifact | Answers | Trust basis | How exposed |
|---|---|---|---|
| **Replay hash** | *What* was checked and *what* it concluded | Pure math — no trust in the producer | recorded with the scan; recompute via the canonical manifest |
| **Signature** | *Who* attested it | The producer's PKI (cert chain → root) | the signature + certificate chain over the hash |
| **Transparency log** | *That* and *when* the signing happened, append-only | Tamper-**evident** (single operator today) | the log entry + its inclusion proof |

The replay hash is the differentiator: change the policy, the asset projection,
the tree structure, or any per-object outcome and you get a **different hash**.
The readable `.esp` policy is the connection between intent and action — it is
what builds the command that produced the verdict. See the canonical spec for
the exact pre-image.

---

## 3. How the transparency log works

The log is an **append-only Merkle tree** implementing RFC 6962 (Certificate
Transparency), used here as a transparency log for **signing identities**.

### 3.1 Hashing (FIPS)

All hashing is SHA-256 through OpenSSL (FIPS-validated in production builds).
RFC-6962 domain separation:

```text
leaf_hash = SHA256(0x00 || data)
node_hash = SHA256(0x01 || left || right)
```

### 3.2 What a leaf commits to

Each leaf records a **signing event**. For the in-process scanner identity the
leaf data is the certificate plus its SAN URI:

```text
leaf_data = certificate_pem || san_uri
leaf_hash = SHA256(0x00 || leaf_data)
```

The same shape is used whenever a signing identity is issued or renewed. The
full certificate PEM, the SAN URI, and an event-kind label are stored alongside
the leaf, so the leaf hash can be recomputed from the stored material.

The log records **who is allowed to sign and that their identity was published**
— it is not a log of scan payloads. The integrity of *what was concluded* lives
in the replay hash + signature, not in the log. (Plainly: the log shows "this
evidence was captured here and when"; the replay hash shows the verdict is
exactly the command reproduced.)

### 3.3 Inclusion proofs

Every signature links to an inclusion-proof record giving an RFC-6962 **inclusion
proof** for its signing event:

| Field | Meaning |
|---|---|
| `log_index` | position of the leaf in the tree |
| `tree_size` | size of the tree when the proof was issued |
| `root_hash` | Merkle root at that size |
| `hashes` | the audit path — sibling hashes leaf→root |

A verifier recomputes the root from `leaf_hash` + the audit path and checks it
equals `root_hash`. This proves the signing event is included in a tree of that
size.

### 3.4 Signed checkpoints (tree heads)

The log periodically emits a **signed checkpoint** — a signed tree head:

```text
SignedCheckpoint { tree_size, root_hash, timestamp, signature, certificate_chain }
signature = ECDSA-P256( SHA256( tree_size(8 BE) || root_hash(32) || timestamp(8 BE) ) )
```

signed by a dedicated **Log Signing** certificate (chain included for offline
verification). A checkpoint lets a consumer pin "the tree looked like this at
this size and time."

### 3.5 What the log does and does not guarantee

- ✅ **Real non-repudiation of issuance.** A signing identity cannot deny that
  its certificate was published and that it issued attestations under it.
- ⚠️ **Tamper-EVIDENT, not tamper-PROOF.** The log is single-operator with no
  external witnessing and no consistency-proof checking yet. A consumer who
  independently saved an earlier checkpoint will *detect* a rewrite, but a
  consumer who trusts the operator's self-published root cannot prove the
  operator never forked or rewound the tree. Closing this needs witnessed tree
  heads + consistency proofs (§6, gap 3). The consistency-proof primitives
  already exist in the Merkle layer.

---

## 4. Verifying an attestation end-to-end

Everything needed is read-only on the verification API (a strictly read-only
access path). Given a `replay_hash`:

### 4.1 Recompute the verdict (binding)

`GET /cmr-api/verify/{replay_hash}` returns a verification bundle:

- `manifest` — the reconstructed canonical manifest (intent + contract + tree),
  rebuilt **on demand**, never persisted: compile the policy → scoped-inject the
  bound asset → resolve (the pipeline up to the moment *before* execution).
- `stored_leaf_hashes` — the per-CTN-per-object v2 leaves recorded at scan time.
- `per_object_outcomes` — the readable pass/fail per object.
- `recomputed_replay_hash` / `matches` — the server's self-check.

A verifier recomputes the v2 rollup from `manifest` + `stored_leaf_hashes` per the
canonical spec and confirms it equals the claimed `replay_hash`. This proves
*this verdict came from this exact, readable check* — with no trust in us.

### 4.2 Check authorship (signature)

The same bundle carries `signature` { `algorithm`, `key_id`, `signature`,
`payload`, `public_key`, `certificate_chain`, `signed_at` }. A verifier checks
the signature over `payload` against `public_key`, then chains `public_key` to a
trusted root via `certificate_chain`.

The signing identity is also available standalone:
`GET /cmr-api/identity/{key_id}` → `{ key_id, signer_id, signer_type, algorithm,
public_key, certificate_chain }`.

### 4.3 Check log inclusion (when/that)

The bundle's `transparency` { `log_index`, `tree_size`, `root_hash`,
`inclusion_proof` } lets a verifier recompute the Merkle root and confirm the
signing event is in the tree (§3.3). The operator surface
`GET /cmr-api/scans/{id}/signature` returns the same anchoring data.

### 4.4 Read the exact logic (don't trust, verify)

`GET /cmr-api/esp-policies/*` serves the precise `.esp` policy source and
`GET /cmr-api/contracts/*` the CTN contract markdown behind every proof — so a
consumer reads the logic that produced the result, not just the result.

---

## 5. Why no evidence leaks

The canonical manifest's outcome layer carries **pass/fail booleans only** — no
raw observed values. The per-CTN leaves are opaque hashes. So the full proof can
be published for verification **without exposing the scanned system's data**. The
cost: a verifier reproduces *verdict ↔ readable check ↔ logged identity*; it does
**not** re-derive the leaves from raw state. That is the deliberate privacy/proof
tradeoff — the bottom of the hash tree is attested, not re-observed.

---

## 6. The honest claim hierarchy

What we have, and what makes the jump to fully independent:

1. **Standalone verifier — NOT shipped.** Today the `matches: true` in the bundle
   is *our server's* recompute. Independent means the consumer runs the recompute
   on their machine from the exposed inputs. Needs an open-source verifier binary
   that takes the bundle and reproduces the hash. **Biggest gap.**
2. **Log-anchored signing key — NOT wired.** The public key in the bundle /
   identity endpoint is served from an operator-mutable store, not cross-checked
   against the transparency-log leaf. A verifier should recompute
   `SHA256(0x00 || cert_pem || san_uri)`, confirm it equals the leaf at
   `log_index`, and confirm the audit path rolls up to `root_hash` — proving the
   key it is checking against is the one that was actually logged.
3. **Witnessing + consistency proofs — NOT shipped.** Required to drop the
   "trusted root" qualifier and hold even against a dishonest operator (§3.5).

Claim ladder:

| When | You may say |
|---|---|
| Today | "Reproducible from exposed inputs; verifiable against a trusted root." |
| After gaps 1 + 2 | "Independently verifiable against a trusted root." |
| After gap 3 | "Independently verifiable" (full — even against a dishonest operator). |

---

## 7. See also

- [replay-hash-canonical-spec.md](replay-hash-canonical-spec.md) — byte-exact
  hash pre-image, rollups, on-demand reconstruction.
- [transparency-log.md](transparency-log.md) — concept overview of the log.
- [pki-and-identity.md](pki-and-identity.md) — the signing identities and chain.
- [posture-and-drift.md](posture-and-drift.md) — posture-as-state and the
  replay-hash hierarchy.
