# k3sdemo

## Azure Ubuntu VM Creation Script

This repository contains a bash script to create an Ubuntu Server in Azure with a user-assigned managed identity.

### Features

- Creates an Ubuntu Server VM with the latest LTS version (Ubuntu 22.04 LTS)
- Creates a user-assigned managed identity
- Assigns the managed identity to the VM
- Grants Contributor role to the identity on the resource group
- Assigns a static public IP address to the VM
- Creates a Network Security Group (NSG) that allows SSH access from the /24 network where the script is launched
- Uses existing RSA SSH key if present, or creates a new one
- Disables password authentication (SSH key-only access)

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
- `LOCATION`: Azure region (default: `swedencentral`)
- `VM_NAME`: Name of the VM (default: `ubuntu-vm`)
- `IDENTITY_NAME`: Name of the managed identity (default: `ubuntu-vm-identity`)
- `VM_SIZE`: VM size (default: `Standard_B4ms`)
- `ADMIN_USERNAME`: Admin username for the VM (default: `azureuser`)

### What the Script Does

1. Validates Azure CLI installation and login status
2. Detects your public IP address and calculates the /24 network range
3. Checks for existing RSA SSH key or creates a new one
4. Creates a resource group in the specified location
5. Creates a Network Security Group with SSH access allowed from your /24 network
6. Creates a static public IP address
7. Creates a user-assigned managed identity
8. Fetches the latest Ubuntu 22.04 LTS image
9. Creates the VM with the managed identity assigned, public IP, and NSG
10. Assigns Contributor role to the identity on the resource group
11. Displays VM connection information

### Security Notes

- The script uses SSH key-based authentication only (password authentication is disabled)
- Uses existing RSA key from `~/.ssh/id_rsa.pub` if available, otherwise generates a new 4096-bit RSA key
- Network Security Group restricts SSH access to the /24 network from where the script is launched
- The managed identity has Contributor access to the resource group
- Static public IP address is assigned for consistent access
- Ensure proper Azure RBAC policies are in place for production use