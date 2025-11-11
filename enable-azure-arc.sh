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
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
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
        
        # Generate Arc agent installation script URL
        ARC_AGENT_SCRIPT_URL="https://aka.ms/azcmagent"
        
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
        
        # Connect the VM to Azure Arc
        print_info "Connecting VM to Azure Arc..."
        
        # Create a service principal for Arc onboarding or use existing credentials
        print_info "Creating service principal for Arc onboarding..."
        SP_NAME="arc-onboarding-${VM_NAME}-$(date +%s)"
        SP_OUTPUT=$(az ad sp create-for-rbac --name "$SP_NAME" --role "Azure Connected Machine Onboarding" --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP")
        SP_APP_ID=$(echo "$SP_OUTPUT" | grep -o '"appId": "[^"]*"' | cut -d'"' -f4)
        SP_PASSWORD=$(echo "$SP_OUTPUT" | grep -o '"password": "[^"]*"' | cut -d'"' -f4)
        SP_TENANT=$(echo "$SP_OUTPUT" | grep -o '"tenant": "[^"]*"' | cut -d'"' -f4)
        
        print_info "Service principal created: $SP_APP_ID"
        
        # Run azcmagent connect on the VM
        print_info "Running azcmagent connect..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo azcmagent connect --service-principal-id '$SP_APP_ID' --service-principal-secret '$SP_PASSWORD' --resource-group '$RESOURCE_GROUP' --tenant-id '$SP_TENANT' --location '$LOCATION' --subscription-id '$SUBSCRIPTION_ID' --resource-name '$VM_NAME-arc'"
        
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
