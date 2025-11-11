# k3sdemo

## Azure Ubuntu VM Creation Script

This repository contains a bash script to create an Ubuntu Server in Azure with a user-assigned managed identity.

### Features

- Creates an Ubuntu Server VM with the latest LTS version (Ubuntu 22.04 LTS)
- Creates a user-assigned managed identity
- Assigns the managed identity to the VM
- Grants Contributor role to the identity on the resource group

### Prerequisites

- Azure CLI installed (`az`)
- Azure subscription with appropriate permissions
- Logged in to Azure (`az login`)

### Usage

Run the script with default settings:

```bash
./create-ubuntu-vm.sh
```

Or customize with environment variables:

```bash
RESOURCE_GROUP="my-rg" \
LOCATION="westus2" \
VM_NAME="my-ubuntu-vm" \
IDENTITY_NAME="my-identity" \
VM_SIZE="Standard_B2ms" \
ADMIN_USERNAME="myadmin" \
./create-ubuntu-vm.sh
```

### Configuration Variables

- `RESOURCE_GROUP`: Name of the resource group (default: `ubuntu-vm-rg`)
- `LOCATION`: Azure region (default: `eastus`)
- `VM_NAME`: Name of the VM (default: `ubuntu-vm`)
- `IDENTITY_NAME`: Name of the managed identity (default: `ubuntu-vm-identity`)
- `VM_SIZE`: VM size (default: `Standard_B2s`)
- `ADMIN_USERNAME`: Admin username for the VM (default: `azureuser`)

### What the Script Does

1. Validates Azure CLI installation and login status
2. Creates a resource group in the specified location
3. Creates a user-assigned managed identity
4. Fetches the latest Ubuntu 22.04 LTS image
5. Creates the VM with the managed identity assigned
6. Assigns Contributor role to the identity on the resource group
7. Displays VM connection information

### Security Notes

- The script uses SSH key-based authentication (generates SSH keys if not present)
- The managed identity has Contributor access to the resource group
- Ensure proper Azure RBAC policies are in place for production use