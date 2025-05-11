#!/bin/bash

#confirm this is a WEKA client
if ! command -v weka >/dev/null 2>&1; then
    echo "WEKA client not found.  Please install WEKA client first"
    exit 1
fi
if weka status >/dev/null 2>&1; then
    echo "User is logged into WEKA, we can proceed"
else
    echo "User is not logged into WEKA or there was an error"
    echo ""
    echo "Run this command when the client is ready:"
    echo ""
    echo "weka user login"
    exit 1
fi
#promot for a TOKEN
read -s -p "Enter your get.weka.io token: " TOKEN

# grab WEKA HOME and install it
curl -LO https://$TOKEN@get.weka.io/dist/v1/lwh/3.2.15/wekahome-3.2.15.bundle
bash wekahome-3.2.15.bundle
/opt/wekahome/current/bin/homecli local setup
WEKHOMEADMIN=$(kubectl get secret -n home-weka-io wekahome-admin-credentials -o jsonpath='{.data.adminPassword}' | base64 -d)
GRAPHANAPASSWORD=$(kubectl get secret -n home-weka-io wekahome-grafana-credentials  -o jsonpath='{.data.password}' | base64 -d)
ENCRYPTIONKEY=$(kubectl get secret -n home-weka-io wekahome-encryption-key -o jsonpath='{.data.encryptionKey}' | base64 -d)
echo "WEKA HOME ADMIN"
echo $WEKHOMEADMIN
echo "Graphana password"
echo $GRAPHANAPASSWORD
echo "Encryption key"
echo $ENCRYPTIONKEY
#learn local IP
LOCSALIP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n 1)
# enabling local WEKA home
weka cloud enable --cloud-url http://$LOCSALIP
# time to login by pointing browser at 
