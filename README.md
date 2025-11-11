# k3sdemo

A demo environment for running k3s on Ubuntu LTS.

## Quick Start

This repository contains a shell script to quickly install and configure k3s on the latest Ubuntu LTS version.

### Prerequisites

- Ubuntu LTS (20.04, 22.04, or later)
- Root access (via sudo)
- Internet connection

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/johankardell/k3sdemo.git
   cd k3sdemo
   ```

2. Run the installation script:
   ```bash
   sudo ./install-k3s.sh
   ```

The script will:
- Check for root access
- Disable UFW firewall (for demo simplicity)
- Install the latest stable version of k3s
- Configure k3s to run as a systemd daemon
- Set up kubeconfig for kubectl access

### Usage

After installation, you can immediately start using kubectl:

```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Managing k3s Service

Check k3s service status:
```bash
sudo systemctl status k3s
```

View k3s logs:
```bash
sudo journalctl -u k3s -f
```

Restart k3s:
```bash
sudo systemctl restart k3s
```

### Uninstalling

To uninstall k3s:
```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

## Notes

- This is a demo environment intended for short-term use (a few hours)
- Security features like UFW are disabled for simplicity
- The script assumes local access to the VM with root privileges
- k3s runs as a systemd service and will automatically start on boot
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
