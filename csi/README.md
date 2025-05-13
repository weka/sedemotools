## Run the installer

The CSI demo setup script will:

1. Create a CSI user on the WEKA cluster
1. Update the WEKA cluster self signed certificate so we can use HTTPS rather than HTTP
1. Install docker, minicube, kubectl, helm and the WEKA CSI plugin (in that order)
1. Create a YAML file for the secret that will work with no further edits

To run the installer do the following as root:

```
cd sedemotools/csi
./csidemosetup.sh
```

One this has been done, simply follow the process below:

### Apply the secret
The secret file will have been updated with the updated WEKA certificate and the correct WEKA IP address
```
kubectl apply -f wekasecret.yaml
kubectl get secret -n csi-wekafs
```
### Apply the storage classes for directory and filesystem backed PVCs
No edits are needed.
```
kubectl apply -f storageclass-wekafs-dir.yaml
kubectl apply -f storageclass-wekafs-fs.yaml
kubectl get sc storageclass-wekafs-dir
kubectl get sc storageclass-wekafs-fs
```
If you want to see details:
```
kubectl describe sc storageclass-wekafs-dir
kubectl describe sc storageclass-wekafs-fs
```
### Make a directory backed PV
No edits are needed.
```
ls -l /mnt/weka
kubectl apply -f pvc-wekafs-dir.yaml -n csi-wekafs
kubectl get pvc pvc-wekafs-dir -n csi-wekafs
kubectl describe pvc pvc-wekafs-dir -n csi-wekafs
kubectl get pv
```
#### Check the PV once its ready
```
ls -l /mnt/weka
ls -l /mnt/weka/csi-volumes/
```
Run a POD to write to that dir
```
kubectl apply -f pod-app-on-dir.yaml -n csi-wekafs
kubectl get pods -n csi-wekafs
```
### Make a filesystem backed PV
No edits are needed.

First show the current filesystems (so we can confirm a new one is created)
```
weka fs
```
Create a new FS backed PV
```
kubectl apply -f pvc-wekafs-fs.yaml -n csi-wekafs
kubectl get pvc pvc-wekafs-fs -n csi-wekafs
kubectl describe pvc pvc-wekafs-fs -n csi-wekafs
kubectl get pv
```
Show the new FS:
```
weka fs
```
Run a POD to write to that FS
```
kubectl apply -f pod-app-on-fs.yaml -n csi-wekafs
kubectl get pods -n csi-wekafs
```

### Create a static PV
All the examples above create a dynamic PV from a PVC.   In the commands below we need to either create the ***/default/testdir*** folder or we need to edit the PV YAML file with the correct directory name.  The mkdir command example presumes you mounted the default filesystem on /mnt/weka.
```
mkdir /mnt/weka/testdir/
```
or
```
vi pv-wekafs-dir-static.yaml
```
Now create the PV
```
kubectl apply -f pv-wekafs-dir-static.yaml -n csi-wekafs
kubectl get pv pv-wekafs-dir-static
```
Now create the PVC
```
kubectl apply -f pvc-wekafs-dir-static.yaml -n csi-wekafs
kubectl get pvc  pvc-wekafs-dir-static -n csi-wekafs
kubectl describe pvc pvc-wekafs-dir-static -n csi-wekafs
```

### If a clean up is needed here are some example commands
```
kubectl delete sc storageclass-wekafs-fs 
kubectl delete sc storageclass-wekafs-dir 
kubectl delete secret csi-wekafs-secret -n csi-wekafs
kubectl delete pvc pvc-wekafs-dir -n csi-wekafs
kubectl delete pvc pvc-wekafs-fs -n csi-wekafs
```
