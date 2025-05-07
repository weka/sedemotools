### Apply the secret
The secret file will have been updated with the WEKA cert and the correct IP address
```
kubectl apply -f wekasecret.yaml
kubectl get secret -n csi-wekafs
```
### Apply the storage classes for directory and filesystem backed PVCs
```
kubectl apply -f storageclass-wekafs-dir-api.yaml
kubectl apply -f storageclass-wekafs-fs-api.yaml
```
### Make a directory backed PV
```
ls -l /mnt/weka
kubectl apply -f pvc-wekafs-dir.yaml
kubectl get pvc -n csi-wekafs
kubectl describe pvc -n csi-wekafs
kubectl get pv
```
#### Check the PV once its ready
```
ls -l /mnt/weka
ls -l /mnt/weka/csi-volumes/
```
### make a filesystem backed PV and check.  
```
kubectl apply -f pvc-wekafs-fs.yaml -n csi-wekafs
kubectl get pvc -n csi-wekafs
kubectl describe pvc -n csi-wekafs
kubectl get pv
```
#### Check the PV once its ready
```
weka fs
```
### If a clean up is needed
```
kubectl delete sc storageclass-wekafs-fs-api
kubectl delete sc storageclass-wekafs-dir-api
kubectl delete secret csi-wekafs-api-secret -n csi-wekafs
kubectl delete pvc pvc-wekafs-dir -n csi-wekafs
kubectl delete pvc pvc-wekafs-fs-api -n csi-wekafs
```
