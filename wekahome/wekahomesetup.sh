#!/bin/bash
# WEKA Local WEKA Home (LWH) setup — installs LWH on a client node.
# Fetches available versions from get.weka.io, prompts for a version,
# generates a self-signed TLS cert, and runs the bundle installer.
# Run as root on a WEKA client node.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

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

# ─── Token handling ───────────────────────────────────────────────────────────

load_token() {
    # Try .env first
    if [[ -f "$ENV_FILE" ]]; then
        local saved
        saved=$(grep -E '^WEKA_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
        if [[ -n "$saved" ]]; then
            TOKEN="$saved"
            print_ok "Token loaded from .env"
            return 0
        fi
    fi

    echo ""
    read -s -p "  Enter your get.weka.io token (hidden): " TOKEN
    echo ""

    if [[ -z "$TOKEN" ]]; then
        print_error "No token supplied."
        exit 1
    fi
    if (( ${#TOKEN} < 16 )); then
        print_error "Token is too short (minimum 16 characters)."
        exit 1
    fi

    read -p "  Save token to .env for future runs? (y/n): " SAVE_TOKEN
    if [[ "$SAVE_TOKEN" =~ ^[Yy]$ ]]; then
        printf 'WEKA_TOKEN=%s\n' "$TOKEN" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        print_ok "Token saved to ${ENV_FILE}"
    fi
}

# ─── Version selection ────────────────────────────────────────────────────────

select_version() {
    print_info "Fetching available WEKA Home versions from get.weka.io..."
    local api_response
    api_response=$(curl -sf --max-time 10 \
        "https://${TOKEN}@get.weka.io/dist/v1/lwh?page=1&page_size=10" 2>/dev/null)

    if [[ -z "$api_response" ]]; then
        print_warn "Could not fetch version list — check token and connectivity."
        read -p "  Enter version manually (e.g. 4.4.4): " LWH_VERSION
        [[ -z "$LWH_VERSION" ]] && { print_error "No version entered."; exit 1; }
        return
    fi

    # Build arrays from JSON
    local versions_json dates_json notes_json
    if command -v python3 >/dev/null 2>&1; then
        versions_json=$(echo "$api_response" | python3 -c '
import json, sys
data = json.load(sys.stdin).get("objects", [])
print("\n".join(r["id"] for r in data if r.get("id")))
' 2>/dev/null)
        dates_json=$(echo "$api_response" | python3 -c '
import json, sys
data = json.load(sys.stdin).get("objects", [])
for r in data:
    pub = r.get("published_at", r.get("created_at", ""))[:10]
    print(pub)
' 2>/dev/null)
        notes_json=$(echo "$api_response" | python3 -c '
import json, sys, re
data = json.load(sys.stdin).get("objects", [])
for r in data:
    notes = r.get("notes", "")
    # grab first bullet after any heading
    bullets = re.findall(r"[-*]\s+(.+)", notes)
    summary = bullets[0].strip() if bullets else ""
    # strip markdown bold/inline code, truncate
    summary = re.sub(r"\*\*([^*]+)\*\*", r"\1", summary)
    summary = re.sub(r"`[^`]+`", "", summary).strip()
    if len(summary) > 55:
        summary = summary[:52] + "..."
    print(summary)
' 2>/dev/null)
    elif command -v jq >/dev/null 2>&1; then
        versions_json=$(echo "$api_response" | jq -r '.objects[].id' 2>/dev/null)
        dates_json=$(echo "$api_response"    | jq -r '.objects[].published_at // .objects[].created_at | .[0:10]' 2>/dev/null)
        notes_json=$(echo "$api_response"    | jq -r '.objects[].notes | split("\n") | map(select(startswith("- ") or startswith("* "))) | first // "" | ltrimstr("- ") | ltrimstr("* ") | .[0:55]' 2>/dev/null)
    else
        # minimal grep fallback — versions only, no notes
        versions_json=$(echo "$api_response" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')
        dates_json=""
        notes_json=""
    fi

    if [[ -z "$versions_json" ]]; then
        print_warn "Could not parse version list."
        read -p "  Enter version manually (e.g. 4.4.4): " LWH_VERSION
        [[ -z "$LWH_VERSION" ]] && { print_error "No version entered."; exit 1; }
        return
    fi

    # Load arrays
    mapfile -t VER_ARRAY  <<< "$versions_json"
    mapfile -t DATE_ARRAY <<< "$dates_json"
    mapfile -t NOTE_ARRAY <<< "$notes_json"

    echo ""
    echo -e "${BOLD}  Available WEKA Home versions:${NC}"
    echo ""
    printf "  ${CYAN}%-4s  %-10s  %-12s  %s${NC}\n" "#" "Version" "Released" "Highlights"
    printf "  ${CYAN}%-4s  %-10s  %-12s  %s${NC}\n" "---" "-------" "--------" "----------"
    local i
    for i in "${!VER_ARRAY[@]}"; do
        local num=$(( i + 1 ))
        local ver="${VER_ARRAY[$i]}"
        local date="${DATE_ARRAY[$i]:-n/a}"
        local note="${NOTE_ARRAY[$i]:-}"
        printf "  ${CYAN}[%d]${NC}   %-10s  %-12s  %s\n" "$num" "$ver" "$date" "$note"
    done
    echo ""

    read -p "  Select a version [1] or type a custom version: " CHOICE

    if [[ -z "$CHOICE" ]]; then
        LWH_VERSION="${VER_ARRAY[0]}"
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#VER_ARRAY[@]} )); then
        LWH_VERSION="${VER_ARRAY[$((CHOICE-1))]}"
    else
        LWH_VERSION="$CHOICE"
    fi
}

# ─── TLS cert generation ──────────────────────────────────────────────────────

generate_cert() {
    local ip="$1"
    cat > /tmp/openssl-san.cnf <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req
x509_extensions    = v3_req
prompt             = no

[ req_distinguished_name ]
CN = $ip

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $ip
EOF
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout server.key \
        -out server.crt \
        -config /tmp/openssl-san.cnf >/dev/null 2>&1
    rm -f /tmp/openssl-san.cnf
}

# ─── Main ─────────────────────────────────────────────────────────────────────

clear
print_header "WEKA — Local WEKA Home (LWH) Setup"

if [[ "$EUID" -ne 0 ]]; then
    print_error "This script must be run as root."
    exit 1
fi

LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1)
if [[ -z "$LOCAL_IP" ]]; then
    print_error "Could not determine local IP address."
    exit 1
fi
print_ok "Local IP: ${LOCAL_IP}"

# Token
load_token

# Version
select_version
echo ""
print_ok "Using WEKA Home version: ${LWH_VERSION}"

# Self-signed cert
print_info "Generating self-signed TLS certificate for ${LOCAL_IP}..."
generate_cert "$LOCAL_IP"
print_ok "Certificate generated"

# Download bundle
BUNDLE="wekahome-${LWH_VERSION}.bundle"
DOWNLOAD_URL="https://${TOKEN}@get.weka.io/dist/v1/lwh/${LWH_VERSION}/${BUNDLE}"

echo ""
print_info "Downloading ${BUNDLE}..."
if ! curl -# -L -o "$BUNDLE" "$DOWNLOAD_URL"; then
    print_error "Download failed — check version, token, and connectivity."
    exit 1
fi
print_ok "Download complete"

# Install
print_info "Running installer..."
bash "$BUNDLE"
source /etc/profile

# Configure homecli
print_info "Configuring LWH via homecli..."
homecli local setup --tls-cert ./server.crt --tls-key ./server.key
rm -f ./server.crt ./server.key

# Retrieve credentials
WEKAHOME_ADMIN=$(kubectl get secret -n home-weka-io wekahome-admin-credentials \
    -o jsonpath='{.data.adminPassword}' 2>/dev/null | base64 -d)
GRAFANA_PASSWORD=$(kubectl get secret -n home-weka-io wekahome-grafana-credentials \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

echo ""
print_divider
echo -e "${BOLD}  WEKA Home credentials${NC}"
print_divider
printf "  %-22s %s\n" "Admin password:"   "${WEKAHOME_ADMIN:-<run kubectl command above manually>}"
printf "  %-22s %s\n" "Grafana password:" "${GRAFANA_PASSWORD:-<run kubectl command above manually>}"
print_divider
echo ""
echo -e "${BOLD}  Enable local WEKA Home (run on a WEKA client node):${NC}"
echo ""
echo "  weka cloud enable --cloud-url http://${LOCAL_IP}"
echo "  # or with TLS:"
echo "  weka cloud enable --cloud-url https://${LOCAL_IP}"
echo ""
print_info "If accessing from outside the host, ensure port 80/443 is open."
print_divider
echo ""
