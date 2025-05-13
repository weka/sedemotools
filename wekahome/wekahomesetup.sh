#!/bin/bash

# prompt for a TOKEN
read -s -p "Enter your get.weka.io token (it wont appear on the screen): " TOKEN

# grab WEKA HOME and install it
echo "Downloading WEKA home bundle"
curl -LO https://$TOKEN@get.weka.io/dist/v1/lwh/3.2.15/wekahome-3.2.15.bundle
echo "Unpacking WEKA HOME"
bash wekahome-3.2.15.bundle
echo "Installing WEKA HOME"
source /etc/profile
homecli local setup
WEKHOMEADMIN=$(kubectl get secret -n home-weka-io wekahome-admin-credentials -o jsonpath='{.data.adminPassword}' | base64 -d)
GRAPHANAPASSWORD=$(kubectl get secret -n home-weka-io wekahome-grafana-credentials  -o jsonpath='{.data.password}' | base64 -d)
echo "------------------------------------------------------------------"
echo "WEKA HOME password (for admin user)"
echo $WEKHOMEADMIN
echo "Graphana password (for admin user)"
echo $GRAPHANAPASSWORD
echo "------------------------------------------------------------------"
#learn local IP
LOCALIP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n 1)
# enabling local WEKA home
echo "------------------------------------------------------------------"
echo "To enable local WEKA home run this command (you need to be logged into WEKA):"
echo "weka cloud enable --cloud-url http://$LOCALIP"
echo "------------------------------------------------------------------"
echo "If accessing via cloud ensure you have access to the LWH external IP on port 80"
echo "------------------------------------------------------------------"