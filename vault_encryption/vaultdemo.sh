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

# Fallback version list used when the HashiCorp releases API is unreachable.
FALLBACK_VERSIONS="1.19.3
1.19.2
1.19.1
1.19.0
1.18.5
1.18.4
1.18.3
1.18.2
1.18.1
1.18.0"

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

    running_pid=$(pgrep -x "vault" 2>/dev/null || true)
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
    [[ -n "$running_pid" ]]           && print_info "  Vault is running (PID: ${running_pid})"
    [[ "$kms_configured" == "true" ]] && print_info "  WEKA KMS is configured"
    [[ -n "$enc_fs_list" ]]           && print_info "  Encrypted filesystems: ${enc_fs_list}"
    echo ""
    read -p "  Clean up all of the above and start fresh? (y/n): " DO_CLEANUP
    if [[ ! "$DO_CLEANUP" =~ ^[Yy]$ ]]; then
        print_info "Exiting without changes."
        exit 0
    fi

    # Stop Vault
    if [[ -n "$running_pid" ]]; then
        pkill -x vault 2>/dev/null; sleep 1
        print_ok "Vault stopped"
    fi

    if command -v weka >/dev/null 2>&1 && weka status >/dev/null 2>&1; then
        for fs in $enc_fs_list; do
            if weka fs delete "$fs" -f 2>/dev/null; then
                print_ok "Deleted filesystem: ${fs}"
            fi
        done
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

# Fetch the latest stable Vault OSS versions from the HashiCorp releases API.
# Uses curl for the HTTP request so proxy/firewall settings are handled
# consistently with the binary download.
get_vault_versions() {
    local api_response
    api_response=$(curl -sf --max-time 8 \
        "https://api.releases.hashicorp.com/v1/releases/vault?license_class=oss&limit=20" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    if command -v python3 >/dev/null 2>&1; then
        echo "$api_response" | python3 - <<'PY' 2>/dev/null
import json, sys
data = json.load(sys.stdin)
seen = []
for r in data:
    v = r.get('version', '')
    if not any(x in v for x in ['rc', 'beta', 'alpha', '+ent']) and v:
        seen.append(v)
    if len(seen) >= 10:
        break
print('\n'.join(seen))
PY
    elif command -v jq >/dev/null 2>&1; then
        echo "$api_response" \
            | jq -r '.[] | select(.version | test("rc|beta|alpha|\\+ent") | not) | .version' 2>/dev/null \
            | head -10
    else
        echo "$api_response" \
            | grep -o '"version":"[^"]*"' \
            | sed 's/"version":"//;s/"//' \
            | grep -v -E 'rc|beta|alpha|\+ent' \
            | head -10
    fi
}

select_version() {
    print_info "Fetching available Vault versions from HashiCorp..."
    local versions
    versions=$(get_vault_versions)

    if [[ -z "$versions" ]]; then
        print_warn "Could not reach HashiCorp releases API — showing known recent versions."
        versions="$FALLBACK_VERSIONS"
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

# Detect and clean up state from any previous run
check_existing_state

# Pick a Vault version
select_version
echo ""
print_ok "Using Vault version: ${VAULT_VERSION}"

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
open_firewall_port

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

    # ─── Tenant AppRole Example ────────────────────────────────────────────
    echo ""
    read -p "  Run the tenant1 AppRole + filesystem example? (y/n): " RUN_TENANT
    if [[ "$RUN_TENANT" =~ ^[Yy]$ ]]; then
        V="$INSTALL_DIR/vault"

        print_header "Tenant AppRole Example — tenant1"

        # 1. Dedicated transit key for tenant1
        print_info "Step 1/4  Creating dedicated transit key 'tenant1-key'..."
        "$V" write -f transit/keys/tenant1-key >/dev/null
        print_ok "Transit key 'tenant1-key' created"

        # 2. Dedicated policy scoped only to tenant1-key
        print_info "Step 2/4  Creating policy 'tenant1'..."
        cat > "$INSTALL_DIR/tenant1_policy.hcl" <<'HCL'
path "transit/+/tenant1-key" {
  capabilities = ["read", "create", "update"]
}
path "transit/keys/tenant1-key" {
  capabilities = ["read"]
}
HCL
        "$V" policy write tenant1 "$INSTALL_DIR/tenant1_policy.hcl" >/dev/null
        print_ok "Policy 'tenant1' created"

        # 3. AppRole for tenant1
        print_info "Step 3/4  Creating AppRole 'tenant1'..."
        "$V" write auth/approle/role/tenant1 \
            token_policies="tenant1" token_ttl=1h token_max_ttl=4h >/dev/null
        T1_ROLE_ID=$("$V" read -field=role_id auth/approle/role/tenant1/role-id)
        T1_SECRET_ID=$("$V" write -f -field=secret_id auth/approle/role/tenant1/secret-id)
        print_ok "AppRole 'tenant1' created"
        print_divider
        echo -e "${BOLD}  tenant1 AppRole Credentials${NC}"
        print_divider
        printf "  %-14s %s\n" "KEY NAME:"  "tenant1-key"
        printf "  %-14s %s\n" "ROLE_ID:"   "$T1_ROLE_ID"
        printf "  %-14s %s\n" "SECRET_ID:" "$T1_SECRET_ID"
        print_divider

        # 4. Create the tenant1 encrypted filesystem
        print_info "Step 4/4  Creating encrypted filesystem 'tenant1'..."
        if ! weka fs create tenant1 default 50GiB \
                --encrypted \
                --kms-key-identifier tenant1-key \
                --kms-role-id "$T1_ROLE_ID" \
                --kms-secret-id "$T1_SECRET_ID"; then
            print_error "Filesystem creation failed."
            print_info "You may need to shrink the default filesystem first:"
            echo "  weka fs update default --ssd-capacity 100gb"
            echo "  weka fs update default --total-capacity 100gb"
        else
            print_ok "Filesystem 'tenant1' created"
            echo ""
            weka fs --output name,group,availableTotal,status,encrypted --filter name=tenant1 2>/dev/null
        fi

        # ─── Rewrap Part 1: rotate AppRole secret_id ──────────────────────
        print_header "Rewrap — Step 1: Rotate the AppRole secret_id"
        print_info "Generating a new secret_id for the tenant1 AppRole..."
        print_info "(The old secret_id is identified by its accessor and then revoked.)"
        echo ""

        # Collect all current secret_id accessors before generating a new one
        OLD_ACCESSORS=$("$V" list -format=json auth/approle/role/tenant1/secret-id 2>/dev/null \
            | python3 -c "import json,sys; print('\n'.join(json.load(sys.stdin)))" 2>/dev/null || true)

        T1_NEW_SECRET_ID=$("$V" write -f -field=secret_id auth/approle/role/tenant1/secret-id)
        print_ok "New secret_id generated"

        if [[ -n "$OLD_ACCESSORS" ]]; then
            while IFS= read -r acc; do
                "$V" write auth/approle/role/tenant1/secret-id-accessor/destroy \
                    secret_id_accessor="$acc" >/dev/null 2>&1
            done <<< "$OLD_ACCESSORS"
            print_ok "Old secret_id revoked"
        fi

        print_divider
        echo -e "${BOLD}  tenant1 — Rotated Credentials${NC}"
        print_divider
        printf "  %-14s %s\n" "ROLE_ID:"        "$T1_ROLE_ID"
        printf "  %-14s %s\n" "NEW SECRET_ID:"  "$T1_NEW_SECRET_ID"
        print_divider

        # ─── Rewrap Part 2: rotate transit key + WEKA rewrap ──────────────
        print_header "Rewrap — Step 2: Rotate transit key and rewrap filesystem DEK"
        print_info "Rotating the transit key creates a new key version in Vault."
        print_info "WEKA then re-encrypts the filesystem's DEK with the new version."
        echo ""

        "$V" write -f transit/keys/tenant1-key/rotate >/dev/null
        print_ok "Transit key 'tenant1-key' rotated (new key version active)"

        print_info "Rewrapping WEKA filesystem DEK..."
        if weka security kms rewrap 2>/dev/null; then
            print_ok "WEKA filesystem DEK rewrapped with new key version"
        else
            print_warn "'weka security kms rewrap' returned an error or is unavailable"
            print_info "The new key version is active in Vault; WEKA will use it on the next key operation."
        fi

        echo ""
        print_divider
        echo -e "${BOLD}  tenant1 Example Complete${NC}"
        print_divider
        echo ""
        print_info "What was demonstrated:"
        echo "  1. Dedicated transit key (tenant1-key) and policy scoped to that key only"
        echo "  2. Dedicated AppRole with credentials only permitting tenant1-key operations"
        echo "  3. Encrypted filesystem 'tenant1' bound to the tenant1 AppRole"
        echo "  4. AppRole secret_id rotated — old credential revoked via its accessor"
        echo "  5. Transit key rotated and WEKA DEK rewrapped with the new key version"
        echo ""
        echo -e "${BOLD}  Cleanup:${NC}"
        echo "  weka fs delete tenant1 -f"
        echo "  $INSTALL_DIR/vault delete auth/approle/role/tenant1"
        echo "  $INSTALL_DIR/vault write transit/keys/tenant1-key/config deletion_allowed=true"
        echo "  $INSTALL_DIR/vault delete transit/keys/tenant1-key"
        print_divider
    fi

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
