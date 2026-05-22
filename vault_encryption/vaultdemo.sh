#!/bin/bash
# WEKA Vault encryption demo — downloads Vault, starts it in dev mode, and
# optionally wires WEKA's KMS to it.  Run as root on a WEKA client node.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

KEYNAME="weka-key"
INSTALL_DIR="$HOME/vault-dir"

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}================================================================${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}================================================================${NC}"
    echo ""
}
print_ok()      { echo -e "${GREEN}  ✓ $1${NC}"; }
print_warn()    { echo -e "${YELLOW}  ! $1${NC}"; }
print_error()   { echo -e "${RED}  ✗ $1${NC}"; }
print_info()    { echo -e "  $1"; }
print_divider() { echo -e "${CYAN}------------------------------------------------------------------${NC}"; }

# Fetch the latest stable Vault OSS versions from the HashiCorp releases API.
get_vault_versions() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' 2>/dev/null
import urllib.request, json, sys
try:
    url = 'https://api.releases.hashicorp.com/v1/releases/vault?license_class=oss&limit=20'
    data = json.loads(urllib.request.urlopen(url, timeout=8).read())
    seen = []
    for r in data:
        v = r.get('version', '')
        if not any(x in v for x in ['rc', 'beta', 'alpha', '+ent']) and v:
            seen.append(v)
        if len(seen) >= 10:
            break
    print('\n'.join(seen))
except Exception:
    sys.exit(1)
PY
    elif command -v jq >/dev/null 2>&1; then
        curl -sf "https://api.releases.hashicorp.com/v1/releases/vault?license_class=oss&limit=20" 2>/dev/null \
            | jq -r '.[] | select(.version | test("rc|beta|alpha|\\+ent") | not) | .version' 2>/dev/null \
            | head -10
    fi
}

select_version() {
    print_info "Fetching available Vault versions from HashiCorp..."
    local versions
    versions=$(get_vault_versions)

    if [[ -z "$versions" ]]; then
        print_warn "Could not fetch version list — enter a version manually."
        read -p "  Enter Vault version (e.g. 1.19.0): " VAULT_VERSION
        [[ -z "$VAULT_VERSION" ]] && VAULT_VERSION="1.19.0"
        return
    fi

    echo ""
    echo -e "${BOLD}  Available Vault versions (latest first):${NC}"
    echo ""
    local i=1
    local version_array=()
    while IFS= read -r v; do
        printf "  ${CYAN}[%d]${NC}  %s\n" "$i" "$v"
        version_array+=("$v")
        (( i++ ))
    done <<< "$versions"

    echo ""
    read -p "  Select a version [1] or type a custom version: " CHOICE

    if [[ -z "$CHOICE" ]]; then
        VAULT_VERSION="${version_array[0]}"
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#version_array[@]} )); then
        VAULT_VERSION="${version_array[$((CHOICE-1))]}"
    else
        VAULT_VERSION="$CHOICE"
    fi
}

install_vault() {
    local version="$1"
    local url="https://releases.hashicorp.com/vault/${version}/vault_${version}_linux_amd64.zip"
    mkdir -p "$INSTALL_DIR"
    print_info "Downloading Vault ${version}..."
    if ! curl -# -L -o "$INSTALL_DIR/vault.zip" "$url"; then
        print_error "Download failed — check the version number and internet connectivity."
        exit 1
    fi
    unzip -o -q -d "$INSTALL_DIR" "$INSTALL_DIR/vault.zip"
    chmod +x "$INSTALL_DIR/vault"
    rm -f "$INSTALL_DIR/vault.zip"
    print_ok "Vault ${version} installed to ${INSTALL_DIR}"
}

# ─── Main ────────────────────────────────────────────────────────────────────

clear
print_header "WEKA — HashiCorp Vault Encryption Demo"

# Ensure required tools are present
if command -v apt >/dev/null 2>&1; then
    apt install -y unzip curl >/dev/null 2>&1
fi
for cmd in curl unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "Required tool not found: $cmd"
        exit 1
    fi
done

# Pick a Vault version
select_version
echo ""
print_ok "Using Vault version: ${VAULT_VERSION}"

# Stop any already-running Vault process
if pgrep -x "vault" >/dev/null; then
    print_warn "Vault is already running."
    read -p "  Kill the existing instance and continue? (y/n): " KILL_EXISTING
    if [[ "$KILL_EXISTING" =~ ^[Yy]$ ]]; then
        pkill -x vault
        sleep 1
        print_ok "Existing Vault instance stopped."
    else
        print_info "Exiting without changes."
        exit 0
    fi
fi

# Install if missing or a different version
if [ -x "$INSTALL_DIR/vault" ]; then
    CURRENT_VERSION=$("$INSTALL_DIR/vault" version 2>/dev/null | awk 'NR==1 {print $2}' | sed 's/^v//')
    if [ "$CURRENT_VERSION" = "$VAULT_VERSION" ]; then
        print_ok "Vault ${VAULT_VERSION} already installed — skipping download."
    else
        print_info "Replacing version ${CURRENT_VERSION} with ${VAULT_VERSION}..."
        install_vault "$VAULT_VERSION"
    fi
else
    install_vault "$VAULT_VERSION"
fi

# Resolve the node's first routable IP
IPADDR=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
[[ -z "$IPADDR" ]] && IPADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$IPADDR" ]]; then
    print_error "Cannot determine host IP address — check networking."
    exit 1
fi

export VAULT_ADDR="http://$IPADDR:8200"

export VAULT_TOKEN="root"

print_info "Starting Vault in dev mode at ${VAULT_ADDR}..."
"$INSTALL_DIR/vault" server -dev -dev-listen-address="$IPADDR:8200" -dev-root-token-id=root \
    > "$INSTALL_DIR/vault.log" 2>&1 &
VAULT_PID=$!
echo "$VAULT_PID" > "$INSTALL_DIR/vault.pid"

# Wait up to 15 s for the API to become ready
READY=0
for i in $(seq 1 15); do
    if "$INSTALL_DIR/vault" status >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [[ "$READY" -eq 0 ]] || ! kill -0 "$VAULT_PID" 2>/dev/null; then
    print_error "Vault failed to start. See: ${INSTALL_DIR}/vault.log"
    exit 1
fi
print_ok "Vault running (PID: ${VAULT_PID}  log: ${INSTALL_DIR}/vault.log)"

echo ""
print_divider
"$INSTALL_DIR/vault" status
print_divider
echo ""

# Configure Vault transit + AppRole for WEKA
"$INSTALL_DIR/vault" secrets enable transit       >/dev/null 2>&1
"$INSTALL_DIR/vault" auth enable approle          >/dev/null 2>&1
"$INSTALL_DIR/vault" write -f transit/keys/weka-key >/dev/null

cat > "$INSTALL_DIR/weka_policy.hcl" <<'HCL'
path "transit/+/weka-key" {
  capabilities = ["read", "create", "update"]
}
path "transit/keys/weka-key" {
  capabilities = ["read"]
}
HCL
"$INSTALL_DIR/vault" policy write weka "$INSTALL_DIR/weka_policy.hcl" >/dev/null

"$INSTALL_DIR/vault" write auth/approle/role/weka \
    token_policies="weka" token_ttl=1h token_max_ttl=4h >/dev/null

ROLE_ID=$("$INSTALL_DIR/vault" read   -field=role_id   auth/approle/role/weka/role-id)
SECRET_ID=$("$INSTALL_DIR/vault" write -f -field=secret_id auth/approle/role/weka/secret-id)

print_divider
echo -e "${BOLD}  WEKA KMS Configuration Values${NC}"
print_divider
printf "  %-12s %s\n" "VAULT_ADDR:" "$VAULT_ADDR"
printf "  %-12s %s\n" "KEY NAME:"   "$KEYNAME"
printf "  %-12s %s\n" "ROLE_ID:"    "$ROLE_ID"
printf "  %-12s %s\n" "SECRET_ID:"  "$SECRET_ID"
print_divider
echo ""

read -p "  Configure WEKA KMS with the values above? (y/n): " CONFIGURE_WEKA

if [[ "$CONFIGURE_WEKA" =~ ^[Yy]$ ]]; then
    if ! command -v weka >/dev/null 2>&1; then
        print_error "WEKA CLI not found on this host."
        echo ""
        print_info "Run the following once the client is ready:"
        echo ""
        echo "  weka security kms set vault $VAULT_ADDR $KEYNAME --role-id $ROLE_ID --secret-id $SECRET_ID"
        exit 1
    fi

    if ! weka status >/dev/null 2>&1; then
        print_error "Not logged into WEKA.  Run: weka user login"
        echo ""
        print_info "Then run:"
        echo ""
        echo "  weka security kms set vault $VAULT_ADDR $KEYNAME --role-id $ROLE_ID --secret-id $SECRET_ID"
        exit 1
    fi
    print_ok "WEKA client authenticated."

    if weka fs -o encrypted --no-header 2>/dev/null | grep -qi "true" || \
       ! weka security kms 2>/dev/null | grep -q "KMS is not configured"; then
        print_error "An encrypted filesystem or KMS is already configured — reset it first."
        exit 1
    fi

    print_info "Configuring WEKA KMS..."
    weka security kms set vault "$VAULT_ADDR" "$KEYNAME" --role-id "$ROLE_ID" --secret-id "$SECRET_ID"

    print_divider
    echo -e "${BOLD}  WEKA KMS Status${NC}"
    print_divider
    weka security kms
    print_divider

    # Create a separate role/secret for filesystem-level encryption
    "$INSTALL_DIR/vault" write -f auth/approle/role/weka-fs-role \
        token_policies="weka" token_ttl=20m >/dev/null
    FS_ROLE_ID=$("$INSTALL_DIR/vault" read   -field=role_id   auth/approle/role/weka-fs-role/role-id)
    FS_SECRET_ID=$("$INSTALL_DIR/vault" write -f -field=secret_id auth/approle/role/weka-fs-role/secret-id)

    echo ""
    print_ok "KMS configured — ready to create encrypted filesystems!"
    echo ""
    echo -e "${BOLD}  Example encrypted filesystem:${NC}"
    echo ""
    echo "  weka fs create test-encrypt default 1TiB \\"
    echo "    --encrypted \\"
    echo "    --kms-key-identifier $KEYNAME \\"
    echo "    --kms-role-id $FS_ROLE_ID \\"
    echo "    --kms-secret-id $FS_SECRET_ID"
    echo ""
    echo -e "${BOLD}  To shrink the default filesystem first:${NC}"
    echo "  weka fs update default --ssd-capacity 100gb"
    echo "  weka fs update default --total-capacity 100gb"
else
    print_divider
    echo -e "${BOLD}  Run this on your WEKA cluster when ready:${NC}"
    echo ""
    echo "  weka security kms set vault $VAULT_ADDR $KEYNAME --role-id $ROLE_ID --secret-id $SECRET_ID"
    print_divider
fi

echo ""
print_ok "Done.  Vault log: ${INSTALL_DIR}/vault.log"
echo ""
