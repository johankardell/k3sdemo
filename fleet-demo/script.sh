#!/bin/bash
set -e

# Variables
RG="rg-demo-fleet"
LOCATION="swedencentral"
FLEET_NAME="demo-fleet"
MEMBER_NAME="k3s-site3"
ARC_RG="rg-site3" 

# Create site3-k3s
./create-vm.sh rg-site3 vm-host3

#############################################################################################################################################
# ssh to vm-host3
sudo ./install-k3s.sh
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  
az login -i
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt
export k3s_cluster_name="k3s-site3"
export resource_group="rg-site3"
export location="swedencentral"
alias k=kubectl
sudo chmod 755 /etc/rancher/k3s/k3s.yaml

az connectedk8s connect --name "$k3s_cluster_name" --resource-group "$resource_group" --location "$location" --kube-config ~/.kube/config

#
# Back to laptop
#############################################################################################################################################


echo "Creating Resource Group $RG..."
az group create --name $RG --location $LOCATION

echo "Creating Azure Kubernetes Fleet Manager $FLEET_NAME..."
# --enable-hub is required to use the hub cluster for placement policies
az fleet create --name $FLEET_NAME --resource-group $RG --location $LOCATION --enable-hub

# use acure cli to assign kubernetes administrator to the current user
CURRENT_USER_UPN=$(az ad signed-in-user show --query userPrincipalName --output tsv)
az role assignment create --assignee $CURRENT_USER_UPN --role "Azure Kubernetes Fleet Manager RBAC Cluster Admin" --scope $(az fleet show --name $FLEET_NAME --resource-group $RG --query id --output tsv)

echo "Retrieving Arc Cluster ID for $MEMBER_NAME..."
# Ensure the connectedk8s extension is installed or available
MEMBER_CLUSTER_ID=$(az connectedk8s show --name $MEMBER_NAME --resource-group $ARC_RG --query id --output tsv)

if [ -z "$MEMBER_CLUSTER_ID" ]; then
    echo "Error: Could not find Arc cluster $MEMBER_NAME in resource group $ARC_RG"
    exit 1
fi

echo "Joining $MEMBER_NAME to the fleet..."
az fleet member create \
    --name $MEMBER_NAME \
    --fleet-name $FLEET_NAME \
    --resource-group $RG \
    --member-cluster-id $MEMBER_CLUSTER_ID

echo "Getting Fleet Hub credentials..."
az fleet get-credentials --name $FLEET_NAME --resource-group $RG

echo "The Hub needs to understand Flux's Custom Resource Definitions to validate your manifests."
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

echo "Applying fleet-flux.yaml..."
kubectl apply -f fleet-demo/fleet-flux.yaml

echo "Check the portal and find the expected error"

kubectl get crp deploy-factory-configs -o yaml

################################################
# ssh to vm-host3 - fix expected error

az k8s-extension create \
  --cluster-name "$k3s_cluster_name" \
  --resource-group "$resource_group" \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux \
  --name flux

kubectl get pods -n default

# if needed to force a reconciliation
kubectl annotate kustomization factory-app-sync -n factory-sim-config \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite

kubectl get pods -n default
################################################

echo "Check the portal and the error should now resolve itself"
