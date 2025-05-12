#!/bin/bash

# prompt for a TOKEN
read -s -p "Enter your get.weka.io token: " TOKEN

# grab WEKA HOME and install it
curl -LO https://$TOKEN@get.weka.io/dist/v1/lwh/3.2.15/wekahome-3.2.15.bundle
sudo bash wekahome-3.2.15.bundle
sudo /opt/wekahome/current/bin/homecli local setup
WEKHOMEADMIN=$(sudo /opt/k3s/bin/kubectl get secret -n home-weka-io wekahome-admin-credentials -o jsonpath='{.data.adminPassword}' | base64 -d)
GRAPHANAPASSWORD=$(sudo /opt/k3s/bin/kubectl get secret -n home-weka-io wekahome-grafana-credentials  -o jsonpath='{.data.password}' | base64 -d)
echo "WEKA HOME password (for admin user)"
echo $WEKHOMEADMIN
echo "Graphana password (for admin user)"
echo $GRAPHANAPASSWORD

#learn local IP
LOCALIP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n 1)
# enabling local WEKA home
echo "To enable local WEKA home run this command:"
echo "weka cloud enable --cloud-url http://$LOCALIP"
echo "If accessing via cloud ensure you have access to the LWH external IP on port 80"