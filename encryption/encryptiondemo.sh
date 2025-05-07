#!/bin/bash

# Prompt user for Vault version
clear
read -p "Enter the Vault version to download and install (press enter for 1.19.0): " VAULT_VERSION

if [[ $VAULT_VERSION == "" ]]; then
    VAULT_VERSION="1.19.0"
fi

# Construct the URL for the specified Vault version
VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"

# we user a fixed keyname
KEYNAME="weka-key"

# Directory to install Vault
INSTALL_DIR="$HOME/vault-dir"

# Check if Vault is already running
if pgrep -x "vault" >/dev/null; then
    echo "Vault is already running."
    read -p "Do you want to kill the existing Vault instance and proceed? (y/n): " KILL_EXISTING
    if [[ "$KILL_EXISTING" == "y" || "$KILL_EXISTING" == "Y" ]]; then
        echo "Killing existing Vault instance..."
        pkill -x vault
    else
        echo "Exiting without changes."
        exit 0
    fi
fi

# Check if Vault is already installed and compare versions
if [ -x "$INSTALL_DIR/vault" ]; then
    CURRENT_VERSION_WITH_V="$($INSTALL_DIR/vault version | awk 'NR==1 {print $2}')"
	CURRENT_VERSION="${CURRENT_VERSION_WITH_V#v}" # Remove the "v" prefix
    if [ "$CURRENT_VERSION" = "$VAULT_VERSION" ]; then
        echo "Vault version $VAULT_VERSION is already installed. Skipping download."
    else
        echo "Downloading Vault version ${VAULT_VERSION}..."
        mkdir -p "$INSTALL_DIR"
        if ! curl -o "$INSTALL_DIR/vault.zip" -L "$VAULT_URL"; then
            echo "Error: Download of Vault version ${VAULT_VERSION} failed."
            exit 1
        fi
        unzip -d "$INSTALL_DIR" "$INSTALL_DIR/vault.zip"
        chmod +x "$INSTALL_DIR/vault"
        rm "$INSTALL_DIR/vault.zip"
    fi
else
    echo "Downloading Vault version ${VAULT_VERSION}..."
    mkdir -p "$INSTALL_DIR"
    if ! curl -o "$INSTALL_DIR/vault.zip" -L "$VAULT_URL"; then
        echo "Error: Download of Vault version ${VAULT_VERSION} failed."
        exit 1
    fi
    unzip -d "$INSTALL_DIR" "$INSTALL_DIR/vault.zip"
    chmod +x "$INSTALL_DIR/vault"
    rm "$INSTALL_DIR/vault.zip"
fi

# Run Vault in development mode
echo "Running Vault in development mode..."
IPADDR=$(ip route get 1 | awk 'NR==1 {print $(NF-2)}')
"$INSTALL_DIR/vault" server -dev -dev-listen-address="$IPADDR:8200" 2>&1 &
# nohup "$INSTALL_DIR/vault" server -dev -dev-listen-address="$IPADDR:8200" > "$INSTALL_DIR/vault.log" 2>&1 &
export VAULT_ADDR="http://$IPADDR:8200"

sleep 1

echo "Vault status:"
echo ""
"$INSTALL_DIR/vault" status
echo ""

# Enable required Vault features
"$INSTALL_DIR/vault" secrets enable transit > /dev/null
"$INSTALL_DIR/vault" auth enable approle > /dev/null


# Create the transit key
"$INSTALL_DIR/vault" write -f transit/keys/weka-key > /dev/null

# Write the weka policy
echo 'path "transit/+/weka-key" {
  capabilities = ["read", "create", "update"]
}
path "transit/keys/weka-key" {
  capabilities = ["read"]
}' > "$INSTALL_DIR/weka_policy.hcl"

# Apply the policy
"$INSTALL_DIR/vault" policy write weka "$INSTALL_DIR/weka_policy.hcl" > /dev/null

# Create the AppRole
"$INSTALL_DIR/vault" write auth/approle/role/weka \
    token_policies="weka" \
    token_ttl=1h \
    token_max_ttl=4h > /dev/null

# Fetch role_id and secret_id
ROLE_ID=$("$INSTALL_DIR/vault" read -field=role_id auth/approle/role/weka/role-id)
SECRET_ID=$("$INSTALL_DIR/vault" write -f -field=secret_id auth/approle/role/weka/secret-id)

# Log in using AppRole
LOGIN_JSON=$("$INSTALL_DIR/vault" write -format=json auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
echo "------------------------------------------------------------------"
echo "Vault Address, Keyname, Role ID and Secret ID for Weka config are:"
echo "VAULT_ADDR: $VAULT_ADDR"
echo "KEYNAME: $KEYNAME"
echo "ROLE_ID: $ROLE_ID"
echo "SECRET_ID: $SECRET_ID"
echo "------------------------------------------------------------------"

read -p "Do you want to configure WEKA using the values above? (y/n): " CONFIGURE_WEKA

if [[ "$CONFIGURE_WEKA" == "y" || "$CONFIGURE_WEKA" == "Y" ]]; then  
    if ! command -v weka >/dev/null 2>&1; then
        echo "Weka client not found"
        echo ""
        echo "Run this command when the client is ready and you are logged in" 
        echo ""
        echo "weka security kms set vault $VAULT_ADDR $KEYNAME --role-id $ROLE_ID --secret-id $SECRET_ID"
        exit 1
    fi

    # Try to run a basic weka command to check authentication
    if weka status >/dev/null 2>&1; then
        echo "User is logged into Weka"
    else
        echo "User is not logged into Weka or there was an error"
        echo ""
        echo "Run this command when the client is ready and you are logged in"
        echo ""
        echo "weka security kms set vault $VAULT_ADDR $KEYNAME --role-id $ROLE_ID --secret-id $SECRET_ID"
        exit 1
    fi

    # now check for encyrption
    if weka fs -o encrypted --no-header | grep -q "True" || ! weka security kms | grep -q "KMS is not configured"; then
        echo "Found an existing encrypted filesystem or configured KMS, quitting."
        exit 1
    else
        echo "Configuring KMS in Weka..."
        # Here, Weka must support AppRole login. If not, you may need to first authenticate and pass the token.
        # weka security kms set vault https://myvault.cse.local:8200 weka-key --role-id 79ab0f17-29af-5a14-cf7e-6e103a36bbdc --secret-id c058e2ac-01b2-7ec9-7c47-51f0d96dd586
        weka security kms set vault "$VAULT_ADDR" "$KEYNAME" --role-id  "$ROLE_ID" --secret-id  "$SECRET_ID"
	echo "------------------------------------------------------------------"
 	weka security kms
  	echo "------------------------------------------------------------------"
        "$INSTALL_DIR/vault" write -f auth/approle/role/weka-role-fs1 token_policies="weka" token_ttl=20m
        FS1ROLE=$("$INSTALL_DIR/vault" read -field=role_id auth/approle/role/weka-role-fs1/role-id)
        FS1SECRET=$("$INSTALL_DIR/vault" write -f -field=secret_id auth/approle/role/weka-role-fs1/secret-id)
        echo ""
        echo "Here is a command to create an encrypted filesystem"
        echo "FS1 role $FS1ROLE"
        echo "FS1 secret $FS1SECRET"
        echo "Example filesystem creation command:"
        echo  "weka fs create test-encrypt default 1TiB --encrypted --kms-key-identifier weka-key --kms-role-id $FS1ROLE --kms-secret-id $FS1SECRET"
    fi
fi


    
