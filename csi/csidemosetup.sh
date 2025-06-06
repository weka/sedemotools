#!/bin/bash
# this script wil install all required files into Amazon Linux 2 to run a CSI demo
if [[ "$EUID" -ne 0 ]]; then
  echo "Error: This script must be run as root."
  exit 1
fi
# we need to be logged into WEKA
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
if command -v apt >/dev/null 2>&1; then
    UBUNTU="y"
else
    UBUNTU="n"
fi
# we create WEKA CSI user as this is best practice
echo "Creating a new CSI user:  wekacsi"
weka user create wekacsi csi "CSIAdmin#"
# the default fs steals all the space, so we shrink it
echo "Shrinking the default FS"
weka fs update default --ssd-capacity 100gb
weka fs update default --total-capacity 100gb
echo "Updating WEKA cert"
# update WEKA cert
./updatecert.sh
# install git 
[[ "$UBUNTU" == "y" ]] && apt install git -y
[[ "$UBUNTU" == "n" ]] && yum install git -y
# install docker
[[ "$UBUNTU" == "y" ]] && apt install docker.io -y
[[ "$UBUNTU" == "n" ]] && yum install docker -y
systemctl start docker
docker ps
# install minicube
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube && rm -f minikube-linux-amd64
minikube start --force
minikube status
minikube kubectl get nodes
# install kubectrl
curl -LO https://dl.k8s.io/release/v1.32.0/bin/linux/amd64/kubectl
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version
#install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh 
./get_helm.sh
helm version
# install CSI plugin
git clone https://github.com/kubernetes-csi/external-snapshotter 
kubectl -n kube-system kustomize external-snapshotter/deploy/kubernetes/snapshot-controller | kubectl create -f -
kubectl kustomize external-snapshotter/client/config/crd | kubectl create -f -
helm repo add csi-wekafs https://weka.github.io/csi-wekafs
helm install csi-wekafs csi-wekafs/csi-wekafsplugin --namespace csi-wekafs --create-namespace
# kubectl get pods -n csi-wekafs
# create secret yaml
weka security tls download crt.pem
cert64=$(base64 -w 0 ./crt.pem)
certdata=$(echo "  caCertificate: "$cert64)
rm -f ./crt.pem
endpoint64=$(echo "$(weka cluster process --filter role=management -o ips --no-header -b | head -1):14000" | base64)
endpoint=$(echo "  endpoints: $endpoint64")
rm -f wekasecret.yaml
cp secretbase.yaml wekasecret.yaml
echo "$endpoint" >> ./wekasecret.yaml
echo "$certdata" >> ./wekasecret.yaml
