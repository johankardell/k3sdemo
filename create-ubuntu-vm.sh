#!/bin/bash

# Script to create an Ubuntu Server in Azure with User-Assigned Managed Identity
# The identity will have contributor role on the resource group

set -e  # Exit on error

# Configuration variables
RESOURCE_GROUP=${RESOURCE_GROUP:-"ubuntu-vm-rg"}
LOCATION=${LOCATION:-"eastus"}
VM_NAME=${VM_NAME:-"ubuntu-vm"}
IDENTITY_NAME=${IDENTITY_NAME:-"ubuntu-vm-identity"}
VM_SIZE=${VM_SIZE:-"Standard_B2s"}
ADMIN_USERNAME=${ADMIN_USERNAME:-"azureuser"}

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

# Create resource group
print_info "Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

print_info "Resource group '$RESOURCE_GROUP' created successfully."

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
    --generate-ssh-keys \
    --assign-identity "$IDENTITY_ID" \
    --output none

print_info "VM '$VM_NAME' created successfully."

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
print_info "VM Details:"
echo "$VM_INFO"
print_info "================================"
print_info "To SSH into the VM, use:"
PUBLIC_IP=$(echo "$VM_INFO" | grep -o '"publicIp": "[^"]*"' | cut -d'"' -f4)
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "null" ]; then
    print_info "ssh $ADMIN_USERNAME@$PUBLIC_IP"
else
    print_info "Public IP not yet assigned. Please check Azure portal."
fi
print_info "================================"
