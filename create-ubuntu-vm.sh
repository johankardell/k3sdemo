#!/bin/bash

# Script to create an Ubuntu Server in Azure with User-Assigned Managed Identity
# The identity will have contributor role on the resource group

set -e  # Exit on error

# Configuration variables
RESOURCE_GROUP=${RESOURCE_GROUP:-"ubuntu-vm-rg"}
LOCATION=${LOCATION:-"swedencentral"}
VM_NAME=${VM_NAME:-"ubuntu-vm"}
IDENTITY_NAME=${IDENTITY_NAME:-"ubuntu-vm-identity"}
VM_SIZE=${VM_SIZE:-"Standard_B4ms"}
ADMIN_USERNAME=${ADMIN_USERNAME:-"azureuser"}
NSG_NAME="${VM_NAME}-nsg"
PUBLIC_IP_NAME="${VM_NAME}-public-ip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

print_info "Starting Azure Ubuntu VM creation process..."
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Location: $LOCATION"
print_info "VM Name: $VM_NAME"
print_info "Identity Name: $IDENTITY_NAME"

# Detect the public IP of the machine running the script
print_info "Detecting your public IP address..."
MY_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")

if [ -z "$MY_IP" ]; then
    print_error "Could not detect your public IP address. Please check your internet connection."
    exit 1
fi

# Calculate the /24 network
IFS='.' read -r -a ip_parts <<< "$MY_IP"
ALLOWED_NETWORK="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.0/24"
print_info "Your public IP: $MY_IP"
print_info "Allowed network: $ALLOWED_NETWORK"

# Check for existing SSH keys
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
if [ -f "$SSH_KEY_PATH" ]; then
    print_info "Found existing RSA key at $SSH_KEY_PATH"
    SSH_KEY_DATA=$(cat "$SSH_KEY_PATH")
else
    print_info "No existing RSA key found. Generating new SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" -C "$ADMIN_USERNAME@$VM_NAME"
    SSH_KEY_DATA=$(cat "$SSH_KEY_PATH")
    print_info "New RSA key pair created at $HOME/.ssh/id_rsa"
fi

# Create resource group
print_info "Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

print_info "Resource group '$RESOURCE_GROUP' created successfully."

# Create Network Security Group
print_info "Creating Network Security Group..."
az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG_NAME" \
    --location "$LOCATION" \
    --output none

print_info "NSG '$NSG_NAME' created successfully."

# Create NSG rule to allow SSH from the /24 network
print_info "Adding NSG rule to allow SSH from $ALLOWED_NETWORK..."
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "AllowSSH" \
    --priority 1000 \
    --source-address-prefixes "$ALLOWED_NETWORK" \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --description "Allow SSH from $ALLOWED_NETWORK" \
    --output none

print_info "NSG rule created successfully."

# Create public IP address
print_info "Creating public IP address..."
az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --location "$LOCATION" \
    --allocation-method Static \
    --sku Standard \
    --output none

print_info "Public IP '$PUBLIC_IP_NAME' created successfully."

# Create user-assigned managed identity
print_info "Creating user-assigned managed identity..."
IDENTITY_ID=$(az identity create \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id \
    --output tsv)

print_info "User-assigned managed identity '$IDENTITY_NAME' created successfully."
print_info "Identity ID: $IDENTITY_ID"

# Get the principal ID of the managed identity
PRINCIPAL_ID=$(az identity show \
    --ids "$IDENTITY_ID" \
    --query principalId \
    --output tsv)

print_info "Principal ID: $PRINCIPAL_ID"

# Get the latest Ubuntu LTS image
print_info "Fetching latest Ubuntu LTS image..."
IMAGE_URN=$(az vm image list \
    --publisher Canonical \
    --offer 0001-com-ubuntu-server-jammy \
    --sku 22_04-lts-gen2 \
    --all \
    --query "[0].urn" \
    --output tsv)

if [ -z "$IMAGE_URN" ]; then
    print_warning "Could not fetch specific image version, using default Ubuntu LTS."
    IMAGE_URN="Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
fi

print_info "Using image: $IMAGE_URN"

# Create the VM with user-assigned managed identity
print_info "Creating Ubuntu VM..."
az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image "$IMAGE_URN" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --ssh-key-values "$SSH_KEY_DATA" \
    --authentication-type ssh \
    --assign-identity "$IDENTITY_ID" \
    --nsg "$NSG_NAME" \
    --public-ip-address "$PUBLIC_IP_NAME" \
    --public-ip-sku Standard \
    --output none

print_info "VM '$VM_NAME' created successfully."

# Configure auto-shutdown at 6 PM Swedish time (18:00 CEST / 17:00 CET)
# Using 1600 UTC which is 18:00 CEST (summer time, most of working year)
# Note: During CET (winter time), this will be 17:00 Swedish time
print_info "Configuring auto-shutdown at 18:00 Swedish time (CEST)..."
az vm auto-shutdown \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --time 1600 \
    --output none

print_info "Auto-shutdown configured successfully (18:00 CEST / 17:00 CET)."

# Get the resource group ID
RG_ID=$(az group show \
    --name "$RESOURCE_GROUP" \
    --query id \
    --output tsv)

print_info "Resource Group ID: $RG_ID"

# Assign Contributor role to the managed identity on the resource group
print_info "Assigning Contributor role to managed identity on resource group..."

# Wait a bit for the identity to propagate
print_info "Waiting for identity to propagate..."
sleep 30

az role assignment create \
    --assignee "$PRINCIPAL_ID" \
    --role "Contributor" \
    --scope "$RG_ID" \
    --output none

print_info "Contributor role assigned successfully."

# Get VM details
print_info "Fetching VM details..."
VM_INFO=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --show-details \
    --query "{publicIp:publicIps, privateIp:privateIps, fqdn:fqdns}" \
    --output json)

print_info "================================"
print_info "VM Creation Complete!"
print_info "================================"
print_info "VM Name: $VM_NAME"
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Location: $LOCATION"
print_info "Admin Username: $ADMIN_USERNAME"
print_info "Managed Identity: $IDENTITY_NAME"
print_info "Auto-Shutdown: 18:00 CEST (17:00 CET) daily"
print_info "VM Details:"
echo "$VM_INFO"
print_info "================================"
print_info "To SSH into the VM, use:"
PUBLIC_IP=$(echo "$VM_INFO" | grep -o '"publicIp": "[^"]*"' | cut -d'"' -f4)
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "null" ]; then
    print_info "ssh $ADMIN_USERNAME@$PUBLIC_IP"
    
    # Wait for VM to boot and SSH to be ready
    print_info "================================"
    print_info "Waiting for VM to boot and SSH to be ready..."
    MAX_WAIT=120
    WAIT_INTERVAL=10
    ELAPSED=0
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$ADMIN_USERNAME@$PUBLIC_IP" "echo 'SSH is ready'" &> /dev/null; then
            print_info "SSH is ready!"
            break
        fi
        print_info "Waiting for SSH... ($ELAPSED seconds elapsed)"
        sleep $WAIT_INTERVAL
        ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        print_warning "Timed out waiting for SSH. You may need to wait a bit longer before connecting."
    else
        # Copy all .sh files to the VM
        print_info "================================"
        print_info "Copying shell scripts to VM..."
        
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        for script in "$SCRIPT_DIR"/*.sh; do
            if [ -f "$script" ]; then
                SCRIPT_NAME=$(basename "$script")
                print_info "Copying $SCRIPT_NAME..."
                if scp -o StrictHostKeyChecking=no "$script" "$ADMIN_USERNAME@$PUBLIC_IP:~/"; then
                    print_info "✓ $SCRIPT_NAME copied successfully"
                else
                    print_warning "Failed to copy $SCRIPT_NAME"
                fi
            fi
        done
        
        print_info "================================"
        print_info "All shell scripts have been copied to the VM's home directory."
    fi
else
    print_info "Public IP not yet assigned. Please check Azure portal."
fi
print_info "================================"
