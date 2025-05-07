#!/bin/bash

# Configuration
WEKA_IP=$(weka cluster process --filter role=management -o ips --no-header -b | head -1)
CERT_PATH="/etc/ssl/weka/weka.crt"
KEY_PATH="/etc/ssl/weka/weka.key"
NEW_CERT="/tmp/weka_new.crt"
NEW_KEY="/tmp/weka_new.key"
SAN_IP="$WEKA_IP"

# Step 1: Download existing cert
echo "[+] Downloading existing certificate from $WEKA_IP..."
openssl s_client -connect ${WEKA_IP}:443 -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM > /tmp/weka_current.crt

# Step 2: Generate new key and config for SAN
echo "[+] Generating new key and OpenSSL config for SAN..."

cat > /tmp/weka_cert.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
C = US
ST = State
L = City
O = Organization
OU = Org Unit
CN = ${WEKA_IP}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = ${SAN_IP}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
EOF

# Step 3: Generate key and CSR
openssl req -new -nodes -newkey rsa:2048 \
  -keyout "$NEW_KEY" -out /tmp/weka.csr \
  -config /tmp/weka_cert.cnf

# Step 4: Self-sign new cert
openssl x509 -req -in /tmp/weka.csr -signkey "$NEW_KEY" -out "$NEW_CERT" \
  -days 365 -extensions v3_ext -extfile /tmp/weka_cert.cnf

echo "[+] New certificate created with IP SAN: $SAN_IP"

# Step 5: Upload/replace on WEKA (manual or via SSH)
weka security tls set --private-key=/tmp/weka_new.key --certificate=/tmp/weka_new.crt
echo "[+] Done. Certificate replaced."
