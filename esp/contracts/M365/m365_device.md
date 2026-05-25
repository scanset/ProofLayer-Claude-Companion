# M365::Device

## Overview

An Entra ID device record. Covers Entra-joined (Azure AD joined),
Hybrid-joined (Server AD + Entra), and Entra-registered (workplace /
BYOD) devices. The `trustType` field is the critical scoping signal —
**Entra-joined corporate devices have full management capability; registered
devices are user-owned and typically have a much narrower compliance
posture**.

**Source:** Microsoft Graph `GET /v1.0/devices`
**Required Graph permission:** `Device.Read.All` (application)

For Intune-managed devices (managed by Microsoft Intune MDM), the
richer record lives at `/deviceManagement/managedDevices`. That's a
**separate Phase 3 asset type** (`M365::ManagedDevice`) — Intune adds
compliance state, configuration profiles, encryption status, and
hardware inventory that the base `/devices` endpoint doesn't carry.

---

## Asset shape

| Field                                | Source (Graph)                       | Notes                                                                                       |
| ------------------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------- |
| `asset_type`                         | constant                             | `M365::Device`                                                                              |
| `provider_id`                        | `id`                                 | Graph object id. Note: `deviceId` is a separate field — see below.                          |
| `display_name`                       | `displayName`                        | Device name (typically hostname for corporate, model-name for BYOD).                        |
| `metadata.device_id`                 | `deviceId`                           | Azure AD device GUID surfaced in claims. Use this to join with sign-in logs / Intune.       |
| `metadata.operating_system`          | `operatingSystem`                    | `Windows`, `macOS`, `iOS`, `Android`, `Linux`.                                              |
| `metadata.operating_system_version`  | `operatingSystemVersion`             |                                                                                             |
| `metadata.trust_type`                | `trustType`                          | **`AzureAd`** = Entra-joined (corp managed). **`ServerAd`** = hybrid. **`Workplace`** = registered (BYOD). |
| `metadata.account_enabled`           | `accountEnabled`                     | Boolean.                                                                                    |
| `metadata.is_compliant`              | `isCompliant`                        | Boolean (from Intune; null if not Intune-managed).                                          |
| `metadata.is_managed`                | `isManaged`                          | Boolean — has an MDM (typically Intune) enrolled.                                           |
| `metadata.registration_date`         | `registrationDateTime`               | When the device first registered.                                                           |
| `metadata.approximate_last_sign_in`  | `approximateLastSignInDateTime`      | Last user sign-in from this device.                                                         |

---

## Common policy uses

- **BYOD posture**: `trustType = 'Workplace'` → confirm conditional access restricts what they can reach
- **Stale devices**: `approximateLastSignInDateTime` older than 90 days AND `accountEnabled = true` → flag for removal
- **Unmanaged corporate**: `trustType = 'AzureAd'` AND `is_managed = false` → should be Intune-enrolled
- **Out-of-compliance**: `is_compliant = false` → Intune policy violations

---

## Note for the test environment

With your setup (1 corporate device Entra-joined, 2 personal devices registered),
you should see:

- 1 row with `trust_type = 'AzureAd'`, likely `is_managed = true`
- 2 rows with `trust_type = 'Workplace'`, `is_managed = false`

---

## Related CTN

[`m365_graph_query`](m365_graph_query.md) — the underlying collector.
