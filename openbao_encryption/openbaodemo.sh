#!/bin/bash
# WEKA OpenBao encryption demo — downloads OpenBao, starts it in dev mode, and
# optionally wires WEKA's KMS to it.  OpenBao is an open-source, community-driven
# fork of HashiCorp Vault (https://openbao.org) and is API-compatible with WEKA's
# Vault KMS integration.  Run as root on a WEKA client node.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

KEYNAME="weka-key"
INSTALL_DIR="$HOME/openbao-dir"
BINARY="$INSTALL_DIR/bao"

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

# Fetch the latest stable OpenBao releases from GitHub.
get_openbao_versions() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' 2>/dev/null
import urllib.request, json, sys
try:
    req = urllib.request.Request(
        'https://api.github.com/repos/openbao/openbao/releases?per_page=20',
        headers={'User-Agent': 'weka-sedemotools'}
    )
    data = json.loads(urllib.request.urlopen(req, timeout=8).read())
    seen = []
    for r in data:
        if r.get('prerelease') or r.get('draft'):
            continue
        v = r.get('tag_name', '').lstrip('v')
        if v:
            seen.append(v)
        if len(seen) >= 10:
            break
    print('\n'.join(seen))
except Exception:
    sys.exit(1)
PY
    elif command -v jq >/dev/null 2>&1; then
        curl -sf -H "User-Agent: weka-sedemotools" \
            "https://api.github.com/repos/openbao/openbao/releases?per_page=20" 2>/dev/null \
            | jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name | ltrimstr("v")' 2>/dev/null \
            | head -10
    fi
}

select_version() {
    print_info "Fetching available OpenBao versions from GitHub..."
    local versions
    versions=$(get_openbao_versions)

    if [[ -z "$versions" ]]; then
        print_warn "Could not fetch version list from GitHub — enter a version manually."
        read -p "  Enter OpenBao version (e.g. 2.2.0): " BAO_VERSION
        [[ -z "$BAO_VERSION" ]] && { print_error "No version specified."; exit 1; }
        return
    fi

    echo ""
    echo -e "${BOLD}  Available OpenBao versions (latest first):${NC}"
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
        BAO_VERSION="${version_array[0]}"
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#version_array[@]} )); then
        BAO_VERSION="${version_array[$((CHOICE-1))]}"
    else
        BAO_VERSION="$CHOICE"
    fi
}

install_openbao() {
    local version="$1"
    local url="https://github.com/openbao/openbao/releases/download/v${version}/bao_${version}_linux_amd64.zip"
    mkdir -p "$INSTALL_DIR"
    print_info "Downloading OpenBao ${version}..."
    if ! curl -# -L -o "$INSTALL_DIR/bao.zip" "$url"; then
        print_error "Download failed — check the version number and internet connectivity."
        exit 1
    fi
    unzip -o -q -d "$INSTALL_DIR" "$INSTALL_DIR/bao.zip"
    chmod +x "$BINARY"
    rm -f "$INSTALL_DIR/bao.zip"
    print_ok "OpenBao ${version} installed to ${INSTALL_DIR}"
}

# ─── Main ────────────────────────────────────────────────────────────────────

clear
print_header "WEKA — OpenBao Encryption Demo"
echo -e "  ${CYAN}OpenBao is an open-source fork of HashiCorp Vault, fully"
echo -e "  compatible with WEKA's Vault KMS integration.${NC}"
echo ""

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

# Pick an OpenBao version
select_version
echo ""
print_ok "Using OpenBao version: ${BAO_VERSION}"

# Stop any already-running bao process
if pgrep -x "bao" >/dev/null; then
    print_warn "OpenBao (bao) is already running."
    read -p "  Kill the existing instance and continue? (y/n): " KILL_EXISTING
    if [[ "$KILL_EXISTING" =~ ^[Yy]$ ]]; then
        pkill -x bao
        sleep 1
        print_ok "Existing OpenBao instance stopped."
    else
        print_info "Exiting without changes."
        exit 0
    fi
fi

# Install if missing or a different version
if [ -x "$BINARY" ]; then
    CURRENT_VERSION=$("$BINARY" version 2>/dev/null | awk 'NR==1 {print $2}' | sed 's/^v//')
    if [ "$CURRENT_VERSION" = "$BAO_VERSION" ]; then
        print_ok "OpenBao ${BAO_VERSION} already installed — skipping download."
    else
        print_info "Replacing version ${CURRENT_VERSION} with ${BAO_VERSION}..."
        install_openbao "$BAO_VERSION"
    fi
else
    install_openbao "$BAO_VERSION"
fi

# Resolve the node's first routable IP
IPADDR=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
[[ -z "$IPADDR" ]] && IPADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$IPADDR" ]]; then
    print_error "Cannot determine host IP address — check networking."
    exit 1
fi

# OpenBao exposes the same HTTP API as Vault; WEKA uses the VAULT_ADDR env var.
export VAULT_ADDR="http://$IPADDR:8200"

print_info "Starting OpenBao in dev mode at ${VAULT_ADDR}..."
"$BINARY" server -dev -dev-listen-address="$IPADDR:8200" \
    > "$INSTALL_DIR/bao.log" 2>&1 &
BAO_PID=$!
echo "$BAO_PID" > "$INSTALL_DIR/bao.pid"
sleep 2

if ! kill -0 "$BAO_PID" 2>/dev/null; then
    print_error "OpenBao failed to start. See: ${INSTALL_DIR}/bao.log"
    exit 1
fi
print_ok "OpenBao running (PID: ${BAO_PID}  log: ${INSTALL_DIR}/bao.log)"

echo ""
print_divider
"$BINARY" status
print_divider
echo ""

# Configure OpenBao transit + AppRole for WEKA (same API as Vault)
"$BINARY" secrets enable transit          >/dev/null 2>&1
"$BINARY" auth enable approle             >/dev/null 2>&1
"$BINARY" write -f transit/keys/weka-key >/dev/null

cat > "$INSTALL_DIR/weka_policy.hcl" <<'HCL'
path "transit/+/weka-key" {
  capabilities = ["read", "create", "update"]
}
path "transit/keys/weka-key" {
  capabilities = ["read"]
}
HCL
"$BINARY" policy write weka "$INSTALL_DIR/weka_policy.hcl" >/dev/null

"$BINARY" write auth/approle/role/weka \
    token_policies="weka" token_ttl=1h token_max_ttl=4h >/dev/null

ROLE_ID=$("$BINARY" read   -field=role_id   auth/approle/role/weka/role-id)
SECRET_ID=$("$BINARY" write -f -field=secret_id auth/approle/role/weka/secret-id)

print_divider
echo -e "${BOLD}  WEKA KMS Configuration Values${NC}"
print_divider
printf "  %-12s %s\n" "VAULT_ADDR:" "$VAULT_ADDR"
printf "  %-12s %s\n" "KEY NAME:"   "$KEYNAME"
printf "  %-12s %s\n" "ROLE_ID:"    "$ROLE_ID"
printf "  %-12s %s\n" "SECRET_ID:"  "$SECRET_ID"
print_divider
echo ""
print_info "(WEKA uses the same 'weka security kms set vault' command for OpenBao)"
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
    "$BINARY" write -f auth/approle/role/weka-fs-role \
        token_policies="weka" token_ttl=20m >/dev/null
    FS_ROLE_ID=$("$BINARY" read   -field=role_id   auth/approle/role/weka-fs-role/role-id)
    FS_SECRET_ID=$("$BINARY" write -f -field=secret_id auth/approle/role/weka-fs-role/secret-id)

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
print_ok "Done.  OpenBao log: ${INSTALL_DIR}/bao.log"
echo ""
