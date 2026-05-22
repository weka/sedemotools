# WEKA SE Demo Tools

A collection of scripts for running hands-on WEKA demos and proofs-of-concept on a cloud-deployed cluster.  Each demo is self-contained in its own folder and can be run on a dedicated client or all on the same client node.

---

## Available demos

| Folder | Demo | What it shows |
|--------|------|---------------|
| [`vault_encryption/`](vault_encryption/) | HashiCorp Vault KMS encryption | WEKA filesystem encryption backed by a Vault transit key; AppRole auth; per-tenant isolated keys |
| [`openbao_encryption/`](openbao_encryption/) | OpenBao KMS encryption | Same as above using OpenBao — the open-source, MPL-licensed fork of Vault |
| [`csi/`](csi/) | WEKA CSI driver | Dynamic PVC provisioning (directory- and filesystem-backed) on K3s/minikube; static PVs |
| [`wekahome/`](wekahome/) | Local WEKA Home | Self-hosted WEKA monitoring and management platform; version picker; auto TLS setup |

---

## Prerequisites

- A WEKA cluster deployed in the cloud (AWS `c5n.4xlarge` clients or larger recommended)
- One or more Linux client nodes attached to the cluster
- Root access on the client node(s)
- Internet access from the client node(s)

---

## Getting started

All demos run on a WEKA client node.  The steps below get you from a fresh client to ready-to-run in under two minutes.

### 1 — Log in to a client node and become root

```bash
sudo su -
```

### 2 — Install git if needed

```bash
# RHEL / CentOS / Rocky
yum install git -y

# Ubuntu / Debian
apt install git -y
```

### 3 — Clone this repo

```bash
git clone https://github.com/weka/sedemotools
cd sedemotools
```

### 4 — Run a demo

Navigate to the demo folder and follow its README.  Each script is interactive — it will prompt you for any required inputs.

```bash
# HashiCorp Vault encryption
cd vault_encryption && sudo ./vaultdemo.sh

# OpenBao encryption
cd openbao_encryption && sudo ./openbaodemo.sh

# CSI driver
cd csi && sudo ./csidemosetup.sh

# Local WEKA Home
cd wekahome && sudo ./wekahomesetup.sh
```

---

## Demo summaries

### Vault & OpenBao encryption

Both scripts do the same thing — the only difference is the KMS backend:

- Download and start the KMS server in dev mode (version picker included)
- Enable the transit secrets engine and AppRole auth
- Create a WEKA-specific policy, role, and key
- Optionally configure `weka security kms` automatically
- Print a ready-to-run `weka fs create --encrypted` command

The READMEs also include a **tenant AppRole example** showing how to create isolated transit keys per tenant, create encrypted filesystems, rotate keys, and rewrap filesystem DEKs.

→ [Vault README](vault_encryption/README.md) · [OpenBao README](openbao_encryption/README.md)

---

### CSI driver

- Creates a dedicated CSI user on the WEKA cluster
- Installs Docker, minikube, kubectl, helm, and the WEKA CSI plugin
- Generates a pre-filled Kubernetes secret YAML
- Walks through directory-backed PVCs, filesystem-backed PVCs, and static PVs

→ [CSI README](csi/README.md)

---

### Local WEKA Home

- Prompts for (or loads from `.env`) your get.weka.io token
- Fetches available LWH versions and lets you pick from a table
- Generates a self-signed TLS cert bound to the node's IP
- Downloads and runs the bundle installer, then configures `homecli`
- Prints the admin and Grafana passwords and the `weka cloud enable` command

→ [WEKA Home README](wekahome/README.md)

---

## Notes

- All scripts require root.
- Vault and OpenBao demos run in **dev mode** — data is in memory only and lost on restart.  Do not use in production.
- The `wekahome/.env` file stores your get.weka.io token locally.  It is excluded from git via `.gitignore`.
- Each demo folder has its own README with a full walkthrough, teardown instructions, and a troubleshooting table.
