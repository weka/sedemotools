#!/bin/bash

# GENERATE A SELF SIGNED CERT
# Get the first non-loopback IPv4 address
LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1)

if [ -z "$LOCAL_IP" ]; then
  echo "Could not determine local IP address."
  exit 1
fi

echo "Using local IP for WEKA Home: $LOCAL_IP"
echo "Generating a self signed certificate for WEKA Home"
# Create a temporary OpenSSL config with SAN
cat > openssl-san.cnf <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req
x509_extensions    = v3_req
prompt             = no

[ req_distinguished_name ]
CN = $LOCAL_IP

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $LOCAL_IP
EOF

 Generate the self-signed certificate and private key
 openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout server.key \
  -out server.crt \
  -config openssl-san.cnf >/dev/null 2>&1

# Clean up
rm -f openssl-san.cnf


# prompt for a TOKEN
read -s -p "Enter your get.weka.io token (it wont appear on the screen): " TOKEN

# grab WEKA Home and install it
echo ""
echo "Downloading WEKA Home bundle"
curl -LO https://$TOKEN@get.weka.io/dist/v1/lwh/3.2.15/wekahome-3.2.15.bundle
echo "Unpacking WEKA Home"
bash wekahome-3.2.15.bundle
echo "Installing WEKA Home"
source /etc/profile
# homecli local setup
homecli local setup --tls-cert ./server.crt --tls-key ./server.key
rm -f ./server.crt
rm -f ./server.key
WEKHOMEADMIN=$(kubectl get secret -n home-weka-io wekahome-admin-credentials -o jsonpath='{.data.adminPassword}' | base64 -d)
GRAPHANAPASSWORD=$(kubectl get secret -n home-weka-io wekahome-grafana-credentials  -o jsonpath='{.data.password}' | base64 -d)
echo "------------------------------------------------------------------"
echo "WEKA Home password (for admin user)"
echo $WEKHOMEADMIN
echo "Graphana password (for admin user)"
echo $GRAPHANAPASSWORD
echo "------------------------------------------------------------------"
#learn local IP
LOCALIP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n 1)
# enabling local WEKA Home
echo "------------------------------------------------------------------"
echo "To enable local WEKA Home run the following: (you need to be logged into WEKA):"
echo "weka cloud enable --cloud-url http://$LOCALIP"
echo "or"
echo "weka cloud enable --cloud-url https://$LOCALIP"
echo "------------------------------------------------------------------"
echo "If accessing via cloud ensure you have access to the LWH external IP on port 80 or 443"
echo "------------------------------------------------------------------"