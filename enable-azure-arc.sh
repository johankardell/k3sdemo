#!/bin/bash

# Script to enable Azure Arc for K3s cluster and VM
# This script enables:
# 1. Azure Arc-enabled Servers (for the VM)
# 2. Azure Arc-enabled Kubernetes (for the K3s cluster)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to install Azure CLI
install_azure_cli() {
    print_step "Installing Azure CLI..."
    
    # Detect OS type
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    # Install Azure CLI using the official method
    print_info "Installing Azure CLI for $OS..."
    
    case "$OS" in
        ubuntu|debian)
            # Use the official Azure CLI installation script for Debian/Ubuntu
            if ! curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash; then
                print_error "Azure CLI installation failed"
                exit 1
            fi
            ;;
        rhel|centos|fedora)
            # For RHEL-based systems, import the Microsoft repository key and install
            print_info "Installing Azure CLI for RHEL-based systems..."
            if ! sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; then
                print_error "Failed to import Microsoft GPG key"
                exit 1
            fi
            if ! curl -sL -o /etc/yum.repos.d/azure-cli.repo https://packages.microsoft.com/yumrepos/azure-cli; then
                print_error "Failed to add Azure CLI repository"
                exit 1
            fi
            if ! sudo yum install -y azure-cli; then
                print_error "Azure CLI installation failed"
                exit 1
            fi
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            print_error "Please install Azure CLI manually from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            exit 1
            ;;
    esac
    
    # Verify installation
    if command -v az &> /dev/null; then
        AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
        print_info "Azure CLI installed successfully (version: $AZ_VERSION)"
    else
        print_error "Azure CLI installation failed"
        exit 1
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 --vm-name <VM_NAME> --resource-group <RESOURCE_GROUP> [OPTIONS]"
    echo ""
    echo "Required arguments:"
    echo "  --vm-name <name>           Name of the VM to Arc-enable"
    echo "  --resource-group <name>    Name of the Azure resource group"
    echo ""
    echo "Optional arguments:"
    echo "  --location <location>      Azure region (default: swedencentral)"
    echo "  --cluster-name <name>      Name for the Arc-enabled K3s cluster (default: <VM_NAME>-k3s)"
    echo "  --admin-username <user>    Admin username for VM SSH (default: azureuser)"
    echo "  --ssh-key <path>           Path to SSH private key (default: ~/.ssh/id_rsa)"
    echo "  --skip-vm-arc              Skip Azure Arc enablement for the VM"
    echo "  --skip-k8s-arc             Skip Azure Arc enablement for Kubernetes"
    echo "  --help                     Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --vm-name ubuntu-vm --resource-group ubuntu-vm-rg"
    echo "  $0 --vm-name myvm --resource-group myrg --location westus2"
    echo "  $0 --vm-name myvm --resource-group myrg --skip-vm-arc"
    exit 0
}

# Parse command line arguments
VM_NAME=""
RESOURCE_GROUP=""
LOCATION="swedencentral"
CLUSTER_NAME=""
ADMIN_USERNAME="azureuser"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
SKIP_VM_ARC=false
SKIP_K8S_ARC=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --admin-username)
            ADMIN_USERNAME="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --skip-vm-arc)
            SKIP_VM_ARC=true
            shift
            ;;
        --skip-k8s-arc)
            SKIP_K8S_ARC=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$VM_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
    print_error "Missing required arguments"
    usage
fi

# Set default cluster name if not provided
if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="${VM_NAME}-k3s"
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_warning "Azure CLI is not installed."
    install_azure_cli
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install it first."
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_error "SSH key not found at $SSH_KEY_PATH"
    exit 1
fi

echo "========================================"
echo "Azure Arc Enablement Script"
echo "========================================"
print_info "VM Name: $VM_NAME"
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Location: $LOCATION"
print_info "Cluster Name: $CLUSTER_NAME"
print_info "Skip VM Arc: $SKIP_VM_ARC"
print_info "Skip K8s Arc: $SKIP_K8S_ARC"
echo ""

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_info "Subscription ID: $SUBSCRIPTION_ID"

# Verify that the resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Resource group '$RESOURCE_GROUP' does not exist"
    exit 1
fi

# Verify that the VM exists
if ! az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" &> /dev/null; then
    print_error "VM '$VM_NAME' does not exist in resource group '$RESOURCE_GROUP'"
    exit 1
fi

# Get VM's public IP
print_info "Retrieving VM public IP address..."
VM_PUBLIC_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --show-details --query publicIps -o tsv)
if [ -z "$VM_PUBLIC_IP" ] || [ "$VM_PUBLIC_IP" = "null" ]; then
    print_error "Could not retrieve VM public IP address"
    exit 1
fi
print_info "VM Public IP: $VM_PUBLIC_IP"

# Register required Azure resource providers
print_step "Registering Azure resource providers..."
az provider register --namespace Microsoft.HybridCompute --wait || true
az provider register --namespace Microsoft.GuestConfiguration --wait || true
az provider register --namespace Microsoft.Kubernetes --wait || true
az provider register --namespace Microsoft.KubernetesConfiguration --wait || true
az provider register --namespace Microsoft.ExtendedLocation --wait || true
print_info "Resource providers registered"

# Enable Azure Arc for the VM
if [ "$SKIP_VM_ARC" = false ]; then
    print_step "Enabling Azure Arc for VM (Azure Arc-enabled servers)..."
    
    # Check if Arc agent is already installed on the VM
    print_info "Checking if Azure Connected Machine agent is already installed..."
    if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP" "systemctl is-active --quiet himdsd" 2>/dev/null; then
        print_warning "Azure Connected Machine agent appears to be already installed and running"
    else
        print_info "Installing Azure Connected Machine agent on VM..."
        
        # Download and run the Arc agent installation script on the VM
        print_info "Downloading Arc agent installation script..."
        
        # Create a temporary script to install Arc agent
        TEMP_SCRIPT=$(mktemp)
        cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/bash
set -e

# Download and install Azure Connected Machine agent
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh
bash ~/install_linux_azcmagent.sh

# Clean up
rm -f ~/install_linux_azcmagent.sh
EOF
        
        # Copy and execute the script on the VM
        print_info "Copying installation script to VM..."
        scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$TEMP_SCRIPT" "$ADMIN_USERNAME@$VM_PUBLIC_IP:~/install_arc.sh"
        
        print_info "Installing Arc agent (this may take a few minutes)..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo bash ~/install_arc.sh && rm -f ~/install_arc.sh"
        
        rm -f "$TEMP_SCRIPT"
        print_info "Arc agent installed successfully"
        
        # Generate SSH keys on the VM for Arc operations
        print_info "Generating SSH keys on the VM..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP" "bash -c 'if [ ! -f ~/.ssh/id_rsa ]; then ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N \"\" -C \"arc-enablement@$VM_NAME\"; echo \"SSH key generated successfully\"; else echo \"SSH key already exists\"; fi'"
        
        # Connect the VM to Azure Arc using managed identity
        print_info "Connecting VM to Azure Arc using managed identity..."
        
        # Get the tenant ID
        TENANT_ID=$(az account show --query tenantId -o tsv)
        
        # Get the managed identity client ID from the VM
        print_info "Retrieving managed identity information..."
        IDENTITY_CLIENT_ID=$(az vm identity show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "userAssignedIdentities.*.clientId" -o tsv)
        
        if [ -z "$IDENTITY_CLIENT_ID" ]; then
            print_error "Could not retrieve managed identity client ID from VM"
            exit 1
        fi
        
        print_info "Managed Identity Client ID: $IDENTITY_CLIENT_ID"
        
        # Ensure the managed identity has the required role for Arc onboarding
        print_info "Ensuring managed identity has Azure Connected Machine Onboarding role..."
        az role assignment create \
            --assignee "$IDENTITY_CLIENT_ID" \
            --role "Azure Connected Machine Onboarding" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
            2>/dev/null || print_info "Role assignment already exists or was created"
        
        # Run azcmagent connect on the VM using managed identity
        print_info "Running azcmagent connect with managed identity authentication..."
        
        # Create a script to run on the VM that uses managed identity to get access token
        TEMP_CONNECT_SCRIPT=$(mktemp)
        cat > "$TEMP_CONNECT_SCRIPT" << 'EOF'
#!/bin/bash
set -e

# Get access token from managed identity
echo "Getting access token from managed identity..."
ACCESS_TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F&client_id=IDENTITY_CLIENT_ID_PLACEHOLDER' -H Metadata:true | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to get access token from managed identity"
    exit 1
fi

echo "Access token obtained successfully"

# Connect to Arc using the access token
echo "Connecting to Azure Arc..."
sudo azcmagent connect \
    --resource-group "RESOURCE_GROUP_PLACEHOLDER" \
    --tenant-id "TENANT_ID_PLACEHOLDER" \
    --location "LOCATION_PLACEHOLDER" \
    --subscription-id "SUBSCRIPTION_ID_PLACEHOLDER" \
    --resource-name "VM_NAME_PLACEHOLDER-arc" \
    --access-token "$ACCESS_TOKEN" \
    --correlation-id "$(uuidgen)"

echo "Connected successfully"
EOF
        
        # Replace placeholders in the script
        sed -i "s/IDENTITY_CLIENT_ID_PLACEHOLDER/$IDENTITY_CLIENT_ID/g" "$TEMP_CONNECT_SCRIPT"
        sed -i "s/RESOURCE_GROUP_PLACEHOLDER/$RESOURCE_GROUP/g" "$TEMP_CONNECT_SCRIPT"
        sed -i "s/TENANT_ID_PLACEHOLDER/$TENANT_ID/g" "$TEMP_CONNECT_SCRIPT"
        sed -i "s/LOCATION_PLACEHOLDER/$LOCATION/g" "$TEMP_CONNECT_SCRIPT"
        sed -i "s/SUBSCRIPTION_ID_PLACEHOLDER/$SUBSCRIPTION_ID/g" "$TEMP_CONNECT_SCRIPT"
        sed -i "s/VM_NAME_PLACEHOLDER/$VM_NAME/g" "$TEMP_CONNECT_SCRIPT"
        
        # Copy and execute the script on the VM
        scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$TEMP_CONNECT_SCRIPT" "$ADMIN_USERNAME@$VM_PUBLIC_IP:~/arc_connect.sh"
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP" "bash ~/arc_connect.sh && rm -f ~/arc_connect.sh"
        
        rm -f "$TEMP_CONNECT_SCRIPT"
        
        print_info "VM successfully connected to Azure Arc"
    fi
else
    print_warning "Skipping Azure Arc enablement for VM"
fi

# Enable Azure Arc for Kubernetes (K3s)
if [ "$SKIP_K8S_ARC" = false ]; then
    print_step "Enabling Azure Arc for Kubernetes cluster..."
    
    # Install Azure CLI connectedk8s extension
    print_info "Installing Azure CLI connectedk8s extension..."
    az extension add --name connectedk8s --upgrade -y 2>/dev/null || az extension add --name connectedk8s -y
    
    # Get kubeconfig from the VM
    print_info "Retrieving kubeconfig from VM..."
    TEMP_KUBECONFIG=$(mktemp)
    
    # Note: This requires K3s API server (port 6443) to be accessible from this machine
    # If the NSG doesn't allow this, you may need to add a rule for port 6443
    scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP:/etc/rancher/k3s/k3s.yaml" "$TEMP_KUBECONFIG"
    
    # Replace localhost with VM's public IP in kubeconfig
    sed -i "s/127.0.0.1/$VM_PUBLIC_IP/g" "$TEMP_KUBECONFIG"
    sed -i "s/localhost/$VM_PUBLIC_IP/g" "$TEMP_KUBECONFIG"
    
    # Export kubeconfig for kubectl commands
    export KUBECONFIG="$TEMP_KUBECONFIG"
    
    # Verify kubectl connectivity
    print_info "Verifying kubectl connectivity to K3s cluster..."
    if ! kubectl get nodes &> /dev/null; then
        print_error "Cannot connect to K3s cluster. Please check that K3s is running and accessible."
        rm -f "$TEMP_KUBECONFIG"
        exit 1
    fi
    print_info "Successfully connected to K3s cluster"
    
    # Check if cluster is already Arc-enabled
    print_info "Checking if cluster is already Arc-enabled..."
    if az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Cluster '$CLUSTER_NAME' is already Arc-enabled"
    else
        # Connect K3s cluster to Azure Arc
        print_info "Connecting K3s cluster to Azure Arc (this may take several minutes)..."
        az connectedk8s connect \
            --name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags "ClusterType=K3s" "VM=$VM_NAME"
        
        print_info "K3s cluster successfully connected to Azure Arc"
    fi
    
    # Verify the connection
    print_info "Verifying Arc-enabled Kubernetes connection..."
    az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query "{name:name, state:connectivityStatus, location:location}" -o table
    
    # Clean up temporary kubeconfig
    rm -f "$TEMP_KUBECONFIG"
else
    print_warning "Skipping Azure Arc enablement for Kubernetes"
fi

echo ""
echo "========================================"
echo "Azure Arc Enablement Complete!"
echo "========================================"
if [ "$SKIP_VM_ARC" = false ]; then
    print_info "VM '$VM_NAME' is now Arc-enabled"
    print_info "View in Azure Portal: https://portal.azure.com/#view/Microsoft_Azure_HybridCompute/AzureArcCenterBlade/~/servers"
fi
if [ "$SKIP_K8S_ARC" = false ]; then
    print_info "K3s cluster '$CLUSTER_NAME' is now Arc-enabled"
    print_info "View in Azure Portal: https://portal.azure.com/#view/Microsoft_Azure_HybridCompute/AzureArcCenterBlade/~/kubernetes"
fi
echo "========================================"
