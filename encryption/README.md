# Vault Demo

Use this when testing or demoing vault.

Features:

- Will download any version of Vault you give it
- Will detect if the download failed (version doesn’t exist, etc) and tell you
- Will detect if Vault is already running and prompt you to kill it
- Will detect if Vault is already downloaded, compare the versions and replace with requested version (or skip download if they match)
- Will then spin up vault in dev mode off the first routable IP of the system
- Will spit out all the details you need to configure WEKA with this DEV instance of Vault.
- Will ask you if you want to configure WEKA with the new Vault instance - NOTE you need the WEKA client to be logged into the WEKA cluser (will also detect if you already have a KMS set or have an encrypted FS and stop you)

Using dev-mode server requires no further setup, and your local `vault` CLI will be authenticated to talk to it. This makes it easy to experiment with Vault or start a Vault instance for development. Every feature of Vault is available in "dev" mode. The `-dev` flag just short-circuits a lot of setup to insecure defaults.

**Warning:** Never, ever, ever run a "dev" mode server in production. It is insecure and will lose data on every restart (since it stores data in-memory). It is only made for demo, development or experimentation.

This script is perfect for doing an encryption demo.  Ideally run it on a WEKA client in the cloud.

1. On a WEKA client server make sure WEKA client is running and make sure you are logged into WEKA with:
   
`weka user login` 

2. Show that that no KMS is configured:
```
[root@weka72 ~]# weka security kms
KMS is not configured. Encrypted filesystems are supported with a local encryption key
```

3. Run the script below as root, including the step to configure KMS in WEKA.

`./vaultdemo.sh`

4. Show  that the KMS is now setup:
```
[root@weka72 tmp]# weka security kms
Using an external Vault by HashiCorp configured with:
URL         : http://10.0.65.75:8200
Key name    : weka-key
Auth method : RoleId/SecretId
```

5. Create a file system and choose the encryption option 
`weka fs create testecryption default 10GB --encrypted`

6. Show the encrypted filesystem:
```
[root@weka72 tmp]# weka fs --output name,group,availableTotal,status,encrypted --filter encrypted=True
FILESYSTEM NAME  GROUP    AVAILABLE TOTAL  STATUS  ENCRYPTED
testencryption   default  1.07 GB          READY   True
```

### Using Vault to store a password
Create a WEKA user and store and confirm the password in Vault.
```
weka user create mounttest regular "Password#"
/root/vault-dirvault kv put secret/mounttest username="demo-user" password="Password#"
/root/vault-dirvault kv get secret/mounttest
```
Now the user login can use this:
```
weka user login mounttest "$(/root/vault-dir/vault kv get -field=password secret/mounttest)"
weka user whoami
```

Teardown:

1. Delete any encrypted filesystem
```
weka fs delete test-encrypt -f
```
2. Reset the KMS:
```
weka security kms reset
```
3. Kill and delete the vault installation
```
pkill -x vault
rm -Rf $HOME/vault-dir
```
