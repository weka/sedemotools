## Run the installer

The CSI demo setup script will:

1. Create a CSI user on the WEKA cluster
1. Update the WEKA cluster self signed certificate so we can use HTTPS rather than HTTP
1. Install docker, minicube, kubectl, helm and the WEKA CSI plugin (in that order)
1. Create a YAML file for the secret that will work with no further edits

Make sure your boot disk is at least 20 GB in size (10 GB is too small).

To run the installer do the following as root:

```
cd sedemotools/csi
./csidemosetup.sh
```
Check that the CSI pods are running:
```
kubectl get pods -n csi-wekafs
```
Output should look like this:
```
NAME                                     READY   STATUS    RESTARTS   AGE
csi-wekafs-controller-54c7bc6d6c-6wf4w   6/6     Running   0          3m14s
csi-wekafs-controller-54c7bc6d6c-swp6c   6/6     Running   0          3m14s
csi-wekafs-node-546f4                    3/3     Running   0          3m14s
```

One this has been done, follow the process below:

### Apply the secret
This secret file will have been updated with the WEKA cluster certificate and IP address.
Secret file are namespace specific so we specify the **csi-wekafs** namespace.
```
kubectl apply -f wekasecret.yaml -n csi-wekafs
kubectl get secret -n csi-wekafs
```
### Apply the storage classes for directory and filesystem backed PVCs
No edits are needed.  Storage classes are cluster wide so we do not specify a namespace.
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
### Make a directory backed PVC
In this example we are creating a PVC that generates a dynamic PV.   We first create a namespace for our PVC:
```
kubectl create namespace my-apps
```
We create our PVC:
```
kubectl apply -f pvc-wekafs-dir.yaml -n my-apps
```
We then monitor for the PV to be created. 
```
kubectl get pvc pvc-wekafs-dir -n my-apps
kubectl describe pvc pvc-wekafs-dir -n my-apps
```
Once the PVC is no longer pending, a PV should exist.   PVs are cluster wide so we don't specify a namespace.
```
kubectl get pv
```
#### Confirm the directory was created
The first PV in a file system creates a **csi-volumes** directory and then a PV directory inside it.
```
ls -l /mnt/weka
ls -l /mnt/weka/csi-volumes/
```
#### Create an application pod
We can run a POD to write to that directory.
```
kubectl apply -f pod-app-on-dir.yaml -n my-apps
kubectl get pods -n my-apps
```
### Make a filesystem backed PV
In this example we are creating a PVC that generates a dynamic filesystem.   

First show the current filesystems (so we can confirm a new one is created)
```
weka fs
```
Create a new FS backed PV
```
kubectl apply -f pvc-wekafs-fs.yaml -n my-apps
```
We then monitor for the PV to be created. 
```
kubectl get pvc pvc-wekafs-fs -n my-apps
kubectl describe pvc pvc-wekafs-fs -n my-apps
kubectl get pv
```
Show the new FS:
```
weka fs
```
Run a POD to write to that FS
```
kubectl apply -f pod-app-on-fs.yaml -n my-apps
kubectl get pods -n my-apps
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
kubectl apply -f pv-wekafs-dir-static.yaml -n my-apps
kubectl get pv pv-wekafs-dir-static
```
Now create the PVC
```
kubectl apply -f pvc-wekafs-dir-static.yaml -n my-apps
kubectl get pvc  pvc-wekafs-dir-static -n my-apps
kubectl describe pvc pvc-wekafs-dir-static -n my-apps
```

### If a clean up is needed here are some example commands
```
kubectl delete sc storageclass-wekafs-fs 
kubectl delete sc storageclass-wekafs-dir 
kubectl delete secret csi-wekafs-secret -n csi-wekafs
kubectl delete pvc pvc-wekafs-dir -n my-apps
kubectl delete pvc pvc-wekafs-fs -n my-apps
```
