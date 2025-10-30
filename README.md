This is a repo of scripts to run quick demos of WEKA using a cloud deployed cluster.

**Available demos**

There are scripts to run the following demos:

1.  Demonstrate encyrption using Hashicorp Vault
2.  Demonstrate the CSI driver using K3S
3.  Demonstrate Local WEKA Home

You can run each demo either on a separate client or all on the same client.

**Instructions**

1. Deploy a WEKA cluster with c5n.4xlarge clients or larger
2. Login to a client
3. su to root
```
sudo su -
```
4. Confirm you have git:
```
yum install git -y
```
or
```
apt install git -y
```
5. Clone this repo
```
git clone https://github.com/weka/sedemotools
```
