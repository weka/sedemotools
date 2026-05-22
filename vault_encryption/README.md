# HashiCorp Vault — WEKA Encryption Demo

Use this script when demoing or testing **WEKA's KMS-backed filesystem encryption** with [HashiCorp Vault](https://www.vaultproject.io/).  
It spins up a Vault dev-mode server on the local node and optionally wires it into WEKA in one shot.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux host (amd64) | Ideally a WEKA client node in the cloud |
| Root / sudo access | Required to install packages and run `weka` commands |
| Internet access | To download Vault and query the version list |
| `curl` + `unzip` | Auto-installed via `apt` if missing (Ubuntu/Debian) |
| `python3` **or** `jq` | Used to parse the version list — at least one should be present |
| WEKA client running & logged in | Only needed if you want the script to configure WEKA automatically |

Log in to WEKA before running the script:
```bash
weka user login
```

---

## What the script does

1. Queries the HashiCorp releases API and presents the **10 most recent stable Vault OSS versions** — no hardcoded version number.
2. Downloads and installs the chosen version (skips download if the same version is already present).
3. Detects and offers to stop any already-running Vault instance.
4. Starts Vault in **dev mode** bound to the node's first routable IP on port `8200`.
5. Configures the transit secrets engine, AppRole auth, and a WEKA-specific policy + role.
6. Displays all values needed to configure WEKA's KMS.
7. Optionally runs `weka security kms set vault …` automatically, then prints an example encrypted filesystem command.

> **Warning:** Dev-mode Vault stores everything in memory. Data is lost on restart. Never use this in production — it is purely for demos and testing.

---

## Usage

```bash
chmod +x vaultdemo.sh
sudo ./vaultdemo.sh
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
sudo ./vaultdemo.sh
```
Select a Vault version from the list, let it run, and choose **y** when asked to configure WEKA.

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

### Bonus — Store a WEKA password in Vault
```bash
weka user create mounttest regular "Password#"
~/vault-dir/vault kv put secret/mounttest username="mounttest" password="Password#"
~/vault-dir/vault kv get secret/mounttest

# Log in using the stored secret
weka user login mounttest "$(~/vault-dir/vault kv get -field=password secret/mounttest)"
weka user whoami
```

---

## Teardown

```bash
# 1. Delete the encrypted filesystem
weka fs delete test-encrypt -f

# 2. Remove the KMS configuration
weka security kms reset

# 3. Stop Vault and remove its installation directory
pkill -x vault
rm -rf ~/vault-dir
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Download fails | Check the version number and internet connectivity — the script prints the URL it tried |
| Vault fails to start | Check `~/vault-dir/vault.log` |
| `weka status` fails | Make sure the WEKA client is running and you have run `weka user login` |
| `KMS already configured` error | Run `weka security kms reset` then rerun the script |
| Port 8200 already in use | Kill the existing process: `pkill -x vault` |
