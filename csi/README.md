## Run the installer

The installer will:

1. Create a CSI user on WEKA
1. Update the WEKA Cert so we can use https rather than http
1. Install docker, minicube, kubectl, helm and WEKA CSI plugin (in that order)
1. Create a secret file that will work with no edits

```
cd sedemotools/csi
./csidemosetup.sh
```

One this has been done, simply follow the process below:

### Apply the secret
The secret file will have been updated with the WEKA cert and the correct IP address
```
kubectl apply -f wekasecret.yaml
kubectl get secret -n csi-wekafs
```
### Apply the storage classes for directory and filesystem backed PVCs
```
kubectl apply -f storageclass-wekafs-dir.yaml
kubectl apply -f storageclass-wekafs-fs.yaml
kubectl get sc storageclass-wekafs-dir
kubectl get sc storageclass-wekafs-fs

If you want to see details:

kubectl describe sc storageclass-wekafs-dir
kubectl describe sc storageclass-wekafs-fs
```
### Make a directory backed PV
```
ls -l /mnt/weka
kubectl apply -f pvc-wekafs-dir.yaml -n csi-wekafs
kubectl get pvc -n csi-wekafs
kubectl describe pvc -n csi-wekafs
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
### make a filesystem backed PV and check.  
Show the current filesystems
```
weka fs
```
Create a new FS backed PV
```
kubectl apply -f pvc-wekafs-fs.yaml -n csi-wekafs
kubectl get pvc -n csi-wekafs
kubectl describe pvc -n csi-wekafs
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


#### Create a static PV
Edit the YAML file with the correct directory name
```
vi pv-wekafs-dir-static.yaml
```
Now create the PV
```
kubectl apply -f pv-wekafs-dir-static.yaml -n csi-wekafs
kubectl get pv pv-wekafs-dir-static
```





### If a clean up is needed
```
kubectl delete sc storageclass-wekafs-fs 
kubectl delete sc storageclass-wekafs-dir 
kubectl delete secret csi-wekafs-secret -n csi-wekafs
kubectl delete pvc pvc-wekafs-dir -n csi-wekafs
kubectl delete pvc pvc-wekafs-fs -n csi-wekafs
```
