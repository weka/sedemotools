#!/bin/bash
# WEKA OpenBao encryption demo — installs OpenBao via the native package manager,
# starts it in dev mode, and optionally wires WEKA's KMS to it.
#
# OpenBao is an open-source fork of HashiCorp Vault (https://openbao.org) and is
# API-compatible with WEKA's Vault KMS integration.
# Run as root on a WEKA client node.
#
# Supported platforms: Ubuntu/Debian (deb), RHEL/CentOS/Rocky (rpm)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

KEYNAME="weka-key"
WORK_DIR="$HOME/openbao-dir"   # log + pid files only; binary goes to /usr/bin/bao

# Fallback version list used when api.github.com is unreachable.
# Update periodically or just let the live API take over when accessible.
FALLBACK_VERSIONS="2.5.4
2.5.3
2.5.2
2.5.1
2.5.0
2.4.3
2.4.2
2.4.1
2.4.0
2.3.1"

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

# Detect leftover state from a previous run and offer to clean it all up.
check_existing_state() {
    local running_pid enc_fs_list kms_configured=false needs_cleanup=false

    running_pid=$(pgrep -x "bao" 2>/dev/null || true)
    [[ -n "$running_pid" ]] && needs_cleanup=true

    if command -v weka >/dev/null 2>&1 && weka status >/dev/null 2>&1; then
        if ! weka security kms 2>/dev/null | grep -q "KMS is not configured"; then
            kms_configured=true
            needs_cleanup=true
        fi
        enc_fs_list=$(weka fs -o name,encrypted --no-header 2>/dev/null \
            | awk 'tolower($2)=="true"{print $1}' | tr '\n' ' ' | sed 's/ $//')
        [[ -n "$enc_fs_list" ]] && needs_cleanup=true
    fi

    [[ "$needs_cleanup" == "false" ]] && return 0

    echo ""
    print_warn "Existing state detected from a previous run:"
    [[ -n "$running_pid" ]]   && print_info "  OpenBao is running (PID: ${running_pid})"
    [[ "$kms_configured" == "true" ]] && print_info "  WEKA KMS is configured"
    [[ -n "$enc_fs_list" ]]   && print_info "  Encrypted filesystems: ${enc_fs_list}"
    echo ""
    read -p "  Clean up all of the above and start fresh? (y/n): " DO_CLEANUP
    if [[ ! "$DO_CLEANUP" =~ ^[Yy]$ ]]; then
        print_info "Exiting without changes."
        exit 0
    fi

    # Stop OpenBao
    if [[ -n "$running_pid" ]]; then
        pkill -x bao 2>/dev/null; sleep 1
        print_ok "OpenBao stopped"
    fi

    if command -v weka >/dev/null 2>&1 && weka status >/dev/null 2>&1; then
        # Delete encrypted filesystems
        for fs in $enc_fs_list; do
            if weka fs delete "$fs" -f 2>/dev/null; then
                print_ok "Deleted filesystem: ${fs}"
            fi
        done
        # Reset KMS
        if [[ "$kms_configured" == "true" ]]; then
            weka security kms reset 2>/dev/null
            print_ok "WEKA KMS reset"
        fi
    fi
    echo ""
}

# Open port 8200 so WEKA backend nodes can reach the dev server.
open_firewall_port() {
    local port=8200
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        print_info "Opening port ${port}/tcp in firewalld..."
        firewall-cmd --add-port="${port}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_ok "Port ${port}/tcp opened in firewalld"
    elif command -v iptables >/dev/null 2>&1; then
        if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1; then
            print_info "Adding iptables rule for port ${port}/tcp..."
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
            print_ok "Port ${port}/tcp opened in iptables"
        fi
    fi
}

# Detect package manager
detect_pkg_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    else
        echo ""
    fi
}

# Fetch the latest stable OpenBao releases from GitHub, filtered to those that
# have a .deb or .rpm asset (i.e. a real release, not a pre-release).
# Uses curl for the HTTP request (same tool that downloads the package) so that
# proxy settings and firewall rules are handled consistently.
get_openbao_versions() {
    local api_response
    api_response=$(curl -sf --max-time 8 \
        -H "User-Agent: weka-sedemotools" \
        "https://api.github.com/repos/openbao/openbao/releases?per_page=20" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    if command -v python3 >/dev/null 2>&1; then
        echo "$api_response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
seen = []
for r in data:
    if r.get("prerelease") or r.get("draft"):
        continue
    v = r.get("tag_name", "").lstrip("v")
    names = [a["name"] for a in r.get("assets", [])]
    if any(n.endswith(".deb") or n.endswith(".rpm") for n in names) and v:
        seen.append(v)
    if len(seen) >= 10:
        break
print("\n".join(seen))
' 2>/dev/null
    elif command -v jq >/dev/null 2>&1; then
        echo "$api_response" \
            | jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name | ltrimstr("v")' 2>/dev/null \
            | head -10
    else
        # grep/sed fallback — no jq or python3 available
        echo "$api_response" \
            | grep -o '"tag_name":"v[^"]*"' \
            | sed 's/"tag_name":"v//;s/"//' \
            | head -10
    fi
}

select_version() {
    print_info "Fetching available OpenBao versions from GitHub..."
    local versions
    versions=$(get_openbao_versions)

    if [[ -z "$versions" ]]; then
        print_warn "Could not reach GitHub API — showing known recent versions."
        versions="$FALLBACK_VERSIONS"
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
    local pkg_mgr="$2"
    local tmpfile url

    mkdir -p "$WORK_DIR"

    if [[ "$pkg_mgr" == "apt" ]]; then
        url="https://github.com/openbao/openbao/releases/download/v${version}/openbao_${version}_linux_amd64.deb"
        tmpfile="/tmp/openbao_${version}_linux_amd64.deb"
        print_info "Downloading OpenBao ${version} (deb)..."
        if ! curl -# -L -o "$tmpfile" "$url"; then
            print_error "Download failed — check the version number and connectivity."
            exit 1
        fi
        if ! dpkg -i "$tmpfile" >/dev/null 2>&1; then
            apt-get install -f -y >/dev/null 2>&1
        fi
    else
        url="https://github.com/openbao/openbao/releases/download/v${version}/openbao_${version}_linux_amd64.rpm"
        tmpfile="/tmp/openbao_${version}_linux_amd64.rpm"
        print_info "Downloading OpenBao ${version} (rpm)..."
        if ! curl -# -L -o "$tmpfile" "$url"; then
            print_error "Download failed — check the version number and connectivity."
            exit 1
        fi
        $pkg_mgr install -y "$tmpfile" >/dev/null 2>&1
    fi

    rm -f "$tmpfile"

    if ! command -v bao >/dev/null 2>&1; then
        print_error "Installation failed — 'bao' not found in PATH after install."
        exit 1
    fi
    print_ok "OpenBao ${version} installed ($(command -v bao))"
}

# ─── Main ────────────────────────────────────────────────────────────────────

clear
print_header "WEKA — OpenBao Encryption Demo"
echo -e "  ${CYAN}OpenBao is an open-source fork of HashiCorp Vault, fully"
echo -e "  compatible with WEKA's Vault KMS integration.${NC}"
echo ""

# Check for supported package manager
PKG_MGR=$(detect_pkg_manager)
if [[ -z "$PKG_MGR" ]]; then
    print_error "No supported package manager found (requires apt, dnf, or yum)."
    exit 1
fi
print_ok "Package manager: ${PKG_MGR}"

# Ensure curl is available
if command -v apt >/dev/null 2>&1; then
    apt-get install -y curl >/dev/null 2>&1
fi
if ! command -v curl >/dev/null 2>&1; then
    print_error "curl is required but not found."
    exit 1
fi

# Detect and clean up state from any previous run
check_existing_state

# Pick an OpenBao version
select_version
echo ""
print_ok "Using OpenBao version: ${BAO_VERSION}"

# Install or upgrade
if command -v bao >/dev/null 2>&1; then
    CURRENT_VERSION=$(bao version 2>/dev/null | awk 'NR==1 {print $2}' | sed 's/^v//')
    if [[ "$CURRENT_VERSION" == "$BAO_VERSION" ]]; then
        print_ok "OpenBao ${BAO_VERSION} is already installed — skipping download."
    else
        print_info "Upgrading from ${CURRENT_VERSION} to ${BAO_VERSION}..."
        install_openbao "$BAO_VERSION" "$PKG_MGR"
    fi
else
    install_openbao "$BAO_VERSION" "$PKG_MGR"
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
export VAULT_TOKEN="root"

mkdir -p "$WORK_DIR"
print_info "Starting OpenBao in dev mode at ${VAULT_ADDR}..."
# -dev-root-token-id=root pins the root token to the literal string "root"
# so VAULT_TOKEN=root above is guaranteed to match
bao server -dev -dev-listen-address="$IPADDR:8200" -dev-root-token-id=root \
    > "$WORK_DIR/bao.log" 2>&1 &
BAO_PID=$!
echo "$BAO_PID" > "$WORK_DIR/bao.pid"

# Wait up to 15 s for the API to become ready
READY=0
for i in $(seq 1 15); do
    if bao status >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [[ "$READY" -eq 0 ]] || ! kill -0 "$BAO_PID" 2>/dev/null; then
    print_error "OpenBao failed to start. See: ${WORK_DIR}/bao.log"
    exit 1
fi
print_ok "OpenBao running (PID: ${BAO_PID}  log: ${WORK_DIR}/bao.log)"
open_firewall_port

echo ""
print_divider
bao status
print_divider
echo ""

# Configure OpenBao transit + AppRole for WEKA (same API as Vault)
bao secrets enable transit          >/dev/null 2>&1
bao auth enable approle             >/dev/null 2>&1
bao write -f transit/keys/weka-key >/dev/null

cat > "$WORK_DIR/weka_policy.hcl" <<'HCL'
path "transit/+/weka-key" {
  capabilities = ["read", "create", "update"]
}
path "transit/keys/weka-key" {
  capabilities = ["read"]
}
HCL
bao policy write weka "$WORK_DIR/weka_policy.hcl" >/dev/null

bao write auth/approle/role/weka \
    token_policies="weka" token_ttl=1h token_max_ttl=4h >/dev/null

ROLE_ID=$(bao read   -field=role_id   auth/approle/role/weka/role-id)
SECRET_ID=$(bao write -f -field=secret_id auth/approle/role/weka/secret-id)

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

    if ! weka security kms 2>/dev/null | grep -q "KMS is not configured"; then
        print_warn "WEKA KMS is already configured."
        read -p "  Reset it and reconfigure? (y/n): " RESET_KMS
        if [[ "$RESET_KMS" =~ ^[Yy]$ ]]; then
            weka security kms reset 2>/dev/null
            print_ok "KMS reset"
        else
            print_info "Exiting without changes."
            exit 0
        fi
    fi

    print_info "Configuring WEKA KMS..."
    if ! weka security kms set vault "$VAULT_ADDR" "$KEYNAME" --role-id "$ROLE_ID" --secret-id "$SECRET_ID"; then
        print_error "KMS configuration failed — check that WEKA backend nodes can reach ${VAULT_ADDR}"
        print_info "Common cause: firewall on this host blocking inbound port 8200 from WEKA nodes."
        exit 1
    fi

    print_divider
    echo -e "${BOLD}  WEKA KMS Status${NC}"
    print_divider
    weka security kms
    print_divider

    # Create a separate role/secret for filesystem-level encryption
    bao write -f auth/approle/role/weka-fs-role \
        token_policies="weka" token_ttl=20m >/dev/null
    FS_ROLE_ID=$(bao read   -field=role_id   auth/approle/role/weka-fs-role/role-id)
    FS_SECRET_ID=$(bao write -f -field=secret_id auth/approle/role/weka-fs-role/secret-id)

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
print_ok "Done.  OpenBao log: ${WORK_DIR}/bao.log"
echo ""
