# `ssh_key`

OpenSSH or PEM private key for authenticating to a Unix host. The
canonical credential for host-mode scans (Linux/Rocky/RHEL targets)
dispatched via the SSH channel.

## What it represents

An asymmetric key pair where the private half lives in Prooflayer's
credential store and the public half is in the target host's
`~/.ssh/authorized_keys`. Prooflayer's SSH channel uses the private key
to authenticate as a specific Unix user when running an
`esp_assessor` scan on the host.

## Payload fields

| Field             | Required | Description                                                                         |
|---                |---       |---                                                                                  |
| `private_key_pem` | yes      | PEM- or OpenSSH-encoded private key (secret)                              |
| `username`        | yes      | Login user the key authenticates as (e.g. `ubuntu`, `ec2-user`, `rocky`, `local`)   |
| `port`            | no       | SSH port. Defaults to `22` when omitted                                             |
| `passphrase`      | no       | Optional passphrase if the key was generated with one. Leave blank for unencrypted keys |

`username` is a **required, first-class field** (not metadata) — it pairs with
the key, since a key authorizes a specific user. The create/rotate form blocks
saving without it, so the scan never silently falls back to a default and fails
auth on a non-Azure host.

Two ergonomics safeguards on `private_key_pem`:
- **Trailing newline is normalized automatically.** OpenSSH's parser requires a
  newline after the `-----END ... -----` marker; the SSH channel writes the key
  with exactly one regardless of how it was pasted (none, one, or several). You
  don't need to get the trailing newline right.
- **Create/rotate validates the envelope shape** — a value that isn't
  `-----BEGIN ... PRIVATE KEY-----` (e.g. you pasted the `.pub` public key, or a
  truncated key) is rejected at create time with a clear message, not mid-scan.
  This is a structural check only, so it catches paste mistakes but not
  every malformed key.

The create/rotate form additionally:
- Detects whether the pasted value looks like a PEM private key
  (`-----BEGIN ... PRIVATE KEY-----` header)
- Supports loading from a file (`.pem`, `.key`, `id_rsa`, `id_ed25519`)
- Shows the format (OpenSSH vs PEM vs RSA vs Ed25519) as confirmation

## Username resolution order

The SSH channel picks the login user in this order (first non-empty wins):

1. `metadata.ssh_username` on the **asset** — per-host override (rare; use when
   one host needs a different user than the credential's default)
2. **`username` on the credential payload** ← the normal case
3. `metadata.username` on the credential — **legacy fallback** for creds created
   before `username` was a payload field; re-saving such a cred through the form
   moves it into the payload
4. Azure VM `vm_facts.admin_username`
5. `azureuser` (last-resort default)

## Metadata fields (non-secret, operator-set)

| Key        | Purpose                                                                |
|---         |---                                                                     |
| `username` | **Legacy only** — superseded by the payload `username` field. Still honored as a fallback (see resolution order) so older creds keep working |
| `notes`    | Free-form context (e.g. "FCI handler hosts only")                       |

## How to provision

Generate a new key pair (Ed25519 recommended for new deployments):

```bash
# On a workstation, NOT on the Prooflayer VM
ssh-keygen -t ed25519 -f prooflayer-scanner -C "prooflayer-scanner"
# Produces:
#   prooflayer-scanner       (private key — paste into Prooflayer)
#   prooflayer-scanner.pub   (public key — push to authorized_keys on hosts)
```

Or RSA 4096-bit for legacy compatibility:

```bash
ssh-keygen -t rsa -b 4096 -f prooflayer-scanner -C "prooflayer-scanner"
```

Push the public key to target hosts:

```bash
# Manual one-host install
ssh-copy-id -i prooflayer-scanner.pub user@host

# Or via configuration management (Ansible / Salt / Puppet)
- name: Install prooflayer-scanner public key
  authorized_key:
    user: rocky
    state: present
    key: "{{ lookup('file', 'prooflayer-scanner.pub') }}"
```

Test from the Prooflayer VM:

```bash
ssh -i ~/.ssh/prooflayer-scanner rocky@<target-host> "uname -n"
# Should print the hostname, no password prompt
```

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (e.g. `rocky-fci-hosts`)
2. **Kind**: SSH key
3. **Login username**: the Unix user the key authenticates as (required —
   e.g. `ubuntu`, `ec2-user`, `rocky`, `local`)
4. **Port**: leave `22` unless the host runs sshd elsewhere
5. **Private key (PEM)**: paste the contents of the private key file — the
   `.pub` public key is rejected; a trailing newline is not required
6. **Passphrase**: leave blank if the key was generated without `-p`
7. **Metadata**: any operator notes (`username` here is legacy — use the field above)

## Used by

- **SSH channel** for any host scan targeting a Linux/Unix asset.
  The scanner
  routes to SSH when the asset's `asset_type` indicates Linux + the
  credential kind is `ssh_key`
- Future: host-mode K8s scans (kubectl exec target) reuse the same
  credential when the cluster is fronted by SSH-only bastions

## Rotation

No automatic expiry. Rotate when:
- A user with key access leaves the org
- Annual hygiene
- Suspected key compromise (paste history, accidental git commit, etc.)

Rotation steps:
1. Generate new key pair on a workstation
2. Push new public key to target hosts (in addition to the old one,
   not replacing yet)
3. Paste new private key into Prooflayer's Rotate flow on the credential
4. Run a discovery / scan cycle to verify new key works
5. Remove the old public key from `authorized_keys` on all hosts

## Failure modes

| Symptom                                       | Likely cause                                                              |
|---                                            |---                                                                        |
| `Permission denied (publickey)`               | Public key not installed on host, or `username` is wrong for that key     |
| `Load key "...": invalid format`              | Pre-fix symptom of a missing trailing newline — now auto-normalized; if still seen, the stored key is genuinely corrupt (re-paste) |
| Scan unexpectedly runs Local / dedups          | Asset had no resolvable IP (channel fell back to Local) — confirm `host.private_ip`; fixed for `Network::Host` + cloud `host.*` shapes |
| `Connection refused`                          | sshd not running, or wrong port — set the `port` payload field            |
| Create rejected: "does not look like a PEM private key" | You pasted the `.pub` public key or a truncated key — paste the PRIVATE key |
| Scan starts but fails partway                 | Host's sshd `MaxSessions` limit hit by concurrent scans                    |

## Security notes

- Private key is held as role-scoped plaintext at rest (no app-layer encryption).
- The SSH channel materializes the private key to a per-scan tempdir
  with 0600 perms, then wipes the tempdir at scan end.
- Prefer Ed25519 over RSA — smaller, faster, modern. RSA 4096 is fine
  for legacy compatibility but RSA 2048 should NOT be used for new
  deployments.
- Set a passphrase on the key only if the threat model justifies
  encryption-at-rest beyond the role-scoped store + encrypted-disk
  protections; with a passphrase set, the SSH channel decrypts the key in
  memory at scan time.
- Per-host or per-host-group keys are stronger than a single global
  scanner key (smaller blast radius if any single host is compromised
  and the auth file is exfiltrated).
