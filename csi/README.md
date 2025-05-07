### Apply the secret
```
kubectl apply -f wekasecret.yaml
kubectl get secret -n csi-wekafs
```
### Apply the two sc
```
kubectl apply -f storageclass-wekafs-dir-api.yaml
kubectl apply -f storageclass-wekafs-fs-api.yaml
```
### make a directory backed PV and check
```
ls -l /mnt/weka
kubectl apply -f pvc-wekafs-dir.yaml
kubectl get pvc -n csi-wekafs
kubectl describe pvc -n csi-wekafs
kubectl get pv
ls -l /mnt/weka
ls -l /mnt/weka/csi-volumes/
````

### make a filesystem backed PV
```
kubectl apply -f pvc-wekafs-fs.yaml -n csi-wekafs
kubectl get pvc -n csi-wekafs
kubectl describe pvc -n csi-wekafs
kubectl get pv
weka fs
```

### If clean up is needed
```
kubectl delete sc storageclass-wekafs-fs-api
kubectl delete sc storageclass-wekafs-dir-api
kubectl delete secret csi-wekafs-api-secret -n csi-wekafs
kubectl delete pvc pvc-wekafs-dir -n csi-wekafs
kubectl delete pvc pvc-wekafs-fs -n csi-wekafs
```
