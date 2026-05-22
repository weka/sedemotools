# OpenBao — WEKA Encryption Demo

Use this script when demoing or testing **WEKA's KMS-backed filesystem encryption** with [OpenBao](https://openbao.org/).

OpenBao is a community-maintained, open-source fork of HashiCorp Vault (created after Vault moved to the BUSL licence in 2023).  It is **fully API-compatible** with WEKA's Vault KMS integration, so `weka security kms set vault` works against an OpenBao server without any changes.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux host (amd64) | Ideally a WEKA client node in the cloud |
| Root / sudo access | Required to install packages and run `weka` commands |
| Internet access | To download OpenBao and query the GitHub releases API |
| `curl` + `unzip` | Auto-installed via `apt` if missing (Ubuntu/Debian) |
| `python3` **or** `jq` | Used to parse the version list — at least one should be present |
| WEKA client running & logged in | Only needed if you want the script to configure WEKA automatically |

Log in to WEKA before running the script:
```bash
weka user login
```

---

## What the script does

1. Queries the **GitHub releases API** for OpenBao and presents the 10 most recent stable releases — no hardcoded version number.
2. Downloads and installs the chosen version (skips download if the same version is already present).
3. Detects and offers to stop any already-running OpenBao instance.
4. Starts OpenBao in **dev mode** bound to the node's first routable IP on port `8200`.
5. Configures the transit secrets engine, AppRole auth, and a WEKA-specific policy + role.
6. Displays all values needed to configure WEKA's KMS.
7. Optionally runs `weka security kms set vault …` automatically, then prints an example encrypted filesystem command.

> **Warning:** Dev-mode OpenBao stores everything in memory. Data is lost on restart. Never use this in production — it is purely for demos and testing.

---

## Usage

```bash
chmod +x openbaodemo.sh
sudo ./openbaodemo.sh
```

---

## Demo walkthrough

### 1 — Verify no KMS is configured
```
# weka security kms
KMS is not configured. Encrypted filesystems are supported with a local encryption key
```

### 2 — Run the script
```bash
sudo ./openbaodemo.sh
```
The script fetches the latest releases from GitHub and presents a numbered list:
```
  Available OpenBao versions (latest first):

  [1]  2.2.0
  [2]  2.1.1
  [3]  2.1.0
  ...
```
Select a version, let it run, and choose **y** when asked to configure WEKA.

### 3 — Confirm KMS is now set
```
# weka security kms
Using an external Vault by HashiCorp configured with:
URL         : http://10.0.65.75:8200
Key name    : weka-key
Auth method : RoleId/SecretId
```

### 4 — Create an encrypted filesystem
The script prints the exact command with real IDs at the end of its run:
```bash
weka fs create test-encrypt default 1TiB \
  --encrypted \
  --kms-key-identifier weka-key \
  --kms-role-id <FS_ROLE_ID> \
  --kms-secret-id <FS_SECRET_ID>
```

### 5 — Verify the filesystem is encrypted
```
# weka fs --output name,group,availableTotal,status,encrypted --filter encrypted=True
FILESYSTEM NAME  GROUP    AVAILABLE TOTAL  STATUS  ENCRYPTED
test-encrypt     default  1.07 GB          READY   True
```

---

## Vault vs OpenBao — key differences

| | HashiCorp Vault | OpenBao |
|---|---|---|
| Licence | BUSL (source-available) | MPL 2.0 (open-source) |
| Binary name | `vault` | `bao` |
| Install directory (this script) | `~/vault-dir` | `~/openbao-dir` |
| Download source | releases.hashicorp.com | github.com/openbao/openbao |
| WEKA `kms set` command | `set vault …` | `set vault …` (same) |
| API compatibility with WEKA | ✓ | ✓ |

---

## Teardown

```bash
# 1. Delete the encrypted filesystem
weka fs delete test-encrypt -f

# 2. Remove the KMS configuration
weka security kms reset

# 3. Stop OpenBao and remove its installation directory
pkill -x bao
rm -rf ~/openbao-dir
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Version list is empty | Requires internet access to api.github.com; enter a version manually if blocked |
| Download fails | Check the version number and internet connectivity — the script prints the URL it tried |
| OpenBao fails to start | Check `~/openbao-dir/bao.log` |
| `weka status` fails | Make sure the WEKA client is running and you have run `weka user login` |
| `KMS already configured` error | Run `weka security kms reset` then rerun the script |
| Port 8200 already in use | Kill the existing process: `pkill -x bao` |
