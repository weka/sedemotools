# WEKA Local WEKA Home (LWH) Setup

Use this script to install **Local WEKA Home** on a client VM for demos and testing.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux host (amd64) | WEKA client node; boot disk ≥ 20 GB |
| Root / sudo access | Required throughout |
| Internet access | To download the bundle from get.weka.io |
| `curl` + `openssl` | Usually pre-installed |
| `python3` **or** `jq` | Used to parse the version list |
| get.weka.io token | Used to authenticate downloads |

---

## Token

The script looks for a `.env` file in the same directory:

```
# wekahome/.env
WEKA_TOKEN=your_token_here
```

If the file is not found, you are prompted for the token and offered the option to save it to `.env` for future runs. The file is created with `chmod 600`.

> **Note:** `.env` is listed in `.gitignore` — it will not be committed to the repo.

---

## Usage

```bash
chmod +x wekahomesetup.sh
sudo ./wekahomesetup.sh
```

The script will:

1. Detect the node's local IP and generate a self-signed TLS cert for it.
2. Load (or prompt for) your get.weka.io token.
3. Fetch the latest available LWH versions from `get.weka.io` and present a table:

```
  Available WEKA Home versions:

  #    Version     Released      Highlights
  ---  -------     --------      ----------
  [1]  4.4.4       2026-05-06    Gzip compression for event queries, Grafana security pin
  [2]  4.4.2       2026-03-17    Custom certs in Syslog TLS, HTTP connection reuse fix
  [3]  4.4.1       2026-03-08    Syslog integration, remote sessions in LWH
  ...
```

4. Download and run the chosen version's installer bundle.
5. Run `homecli local setup` with the generated cert.
6. Print the admin and Grafana passwords, and the `weka cloud enable` command.

---

## After installation

```bash
# Enable WEKA to report to this LWH instance (run on a WEKA client node):
weka cloud enable --cloud-url http://<LOCAL_IP>
# or with TLS:
weka cloud enable --cloud-url https://<LOCAL_IP>
```

---

## Teardown

```bash
homecli local teardown
```
