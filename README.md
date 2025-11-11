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

## Azure Arc Enablement Script

This repository contains a shell script to enable Azure Arc for both the VM and the K3s cluster created in this repository.

### What is Azure Arc?

Azure Arc allows you to manage and govern resources outside of Azure (or within Azure) through Azure Resource Manager. This script enables:

1. **Azure Arc-enabled Servers**: Manage the VM as an Azure resource with Azure management capabilities
2. **Azure Arc-enabled Kubernetes**: Manage the K3s cluster through Azure, enabling GitOps, Azure Policy, and other Azure services

### Prerequisites

- Azure CLI installed and configured (`az login`)
- kubectl installed
- An existing Azure VM created with `create-ubuntu-vm.sh`
- K3s installed on the VM using `install-k3s.sh`
- SSH access to the VM
- **Network access**: The K3s API server (port 6443) must be accessible from the machine running this script. You may need to add an NSG rule to allow this:
  ```bash
  az network nsg rule create \
    --resource-group <RESOURCE_GROUP> \
    --nsg-name <VM_NAME>-nsg \
    --name AllowK3sAPI \
    --priority 1100 \
    --source-address-prefixes <YOUR_IP>/32 \
    --destination-port-ranges 6443 \
    --access Allow \
    --protocol Tcp
  ```
- Required Azure permissions to register resource providers and create Arc resources

### Usage

Enable both Azure Arc for the VM and K3s cluster:

```bash
./enable-azure-arc.sh --vm-name ubuntu-vm --resource-group ubuntu-vm-rg
```

Customize the location and cluster name:

```bash
./enable-azure-arc.sh \
  --vm-name ubuntu-vm \
  --resource-group ubuntu-vm-rg \
  --location westus2 \
  --cluster-name my-k3s-cluster
```

Enable only Kubernetes Arc (skip VM Arc):

```bash
./enable-azure-arc.sh \
  --vm-name ubuntu-vm \
  --resource-group ubuntu-vm-rg \
  --skip-vm-arc
```

Enable only VM Arc (skip Kubernetes Arc):

```bash
./enable-azure-arc.sh \
  --vm-name ubuntu-vm \
  --resource-group ubuntu-vm-rg \
  --skip-k8s-arc
```

### Configuration Options

The script accepts the following parameters:

**Required:**
- `--vm-name`: Name of the VM to Arc-enable
- `--resource-group`: Name of the Azure resource group

**Optional:**
- `--location`: Azure region (default: `swedencentral`)
- `--cluster-name`: Name for the Arc-enabled K3s cluster (default: `<VM_NAME>-k3s`)
- `--admin-username`: Admin username for VM SSH (default: `azureuser`)
- `--ssh-key`: Path to SSH private key (default: `~/.ssh/id_rsa`)
- `--skip-vm-arc`: Skip Azure Arc enablement for the VM
- `--skip-k8s-arc`: Skip Azure Arc enablement for Kubernetes
- `--help`: Display help message

### What the Script Does

1. Validates prerequisites (Azure CLI, kubectl, SSH key)
2. Registers required Azure resource providers
3. For VM Arc-enablement:
   - Generates SSH keys on the VM (if not already present)
   - Installs Azure Connected Machine agent on the VM
   - Connects the VM to Azure Arc-enabled servers using the VM's managed identity for authentication
4. For Kubernetes Arc-enablement:
   - Installs Azure CLI connectedk8s extension
   - Retrieves kubeconfig from the VM
   - Connects the K3s cluster to Azure Arc-enabled Kubernetes
5. Provides links to view resources in Azure Portal

### After Arc Enablement

Once enabled, you can:

- View and manage the VM in Azure Portal under Arc-enabled servers
- View and manage the K3s cluster in Azure Portal under Arc-enabled Kubernetes
- Apply Azure Policies to the cluster
- Use GitOps with Azure Arc
- Monitor the cluster with Azure Monitor
- Deploy Azure services to the cluster

### Azure Portal Links

- View Arc-enabled servers: https://portal.azure.com/#view/Microsoft_Azure_HybridCompute/AzureArcCenterBlade/~/servers
- View Arc-enabled Kubernetes: https://portal.azure.com/#view/Microsoft_Azure_HybridCompute/AzureArcCenterBlade/~/kubernetes

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
