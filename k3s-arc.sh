export k3s_cluster_name="ubuntu-k3s"
export resource_group="ubuntu-vm-rg"
export location="swedencentral"

sudo chmod 750 /etc/rancher/k3s/k3s.yaml

curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  

az login -i
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# Arc enable k3s
az connectedk8s connect --name "$k3s_cluster_name" --resource-group "$resource_group" --location "$location" --kube-config ~/.kube/config

# Setup configuration for Azure portal

kubectl create serviceaccount azure-portal-user -n default
kubectl create clusterrolebinding azure-portal-user-binding --clusterrole cluster-admin --serviceaccount default:azure-portal-user

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: azure-portal-user-secret
  annotations:
    kubernetes.io/service-account.name: azure-portal-user
type: kubernetes.io/service-account-token
EOF

TOKEN=$(kubectl get secret azure-portal-user-secret -o jsonpath='{$.data.token}' | base64 -d | sed 's/$/\n/g')

echo Paste this into the Azure portal: $TOKEN
