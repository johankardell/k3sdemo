# K3S LAB

## 1
Select correct lab subscription and register resource providers

```sh
az account set -s lab-subscription

az provider register --namespace "Microsoft.KubernetesConfiguration"
az provider register --namespace "Microsoft.ExtendedLocation"
az provider register --namespace "Microsoft.Kubernetes"

az extension add --name connectedk8s
az extension add --name k8s-extension
az extension add --name k8s-configuration

az extension update --name connectedk8s
az extension update --name k8s-extension
az extension update --name k8s-configuration

```

### Policy assignment
Assign the policy 'Kubernetes cluster containers CPU and memory resource requests must be defined' to the subscription of the lab.

## 2
Create Lab server 1

Run from laptop

```sh
./create-vm.sh rg-site1 vm-host1
```

## Run from vm-host1
Install K3s

```sh
sudo ./install-k3s.sh
```

### Install Azure cli on vm-host1

```sh
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  

az login -i
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt
```

### Enable ARC on k3s cluster
```sh
export k3s_cluster_name="k3s-site1"
export resource_group="rg-site1"
export location="swedencentral"
alias k=kubectl
sudo chmod 755 /etc/rancher/k3s/k3s.yaml

az connectedk8s connect --name "$k3s_cluster_name" --resource-group "$resource_group" --location "$location" --kube-config ~/.kube/config

```

### Setup Flux
```sh
# Enable Flux extension on Arc-enabled cluster
az k8s-extension create \
  --cluster-name "$k3s_cluster_name" \
  --resource-group "$resource_group" \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux \
  --name flux

# Create Flux configuration to sync application from GitHub
az k8s-configuration flux create \
  --cluster-name "$k3s_cluster_name" \
  --resource-group "$resource_group" \
  --cluster-type connectedClusters \
  --name flux-config \
  --namespace flux-system \
  --scope cluster \
  --url https://github.com/johankardell/k3sdemo \
  --branch main \
  --kustomization name=flux path=./flux prune=true
```

### Setup configuration for Azure portal (Service account token authentication)
```sh
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
```

### Use kubectl from your laptop
Open a terminal on your laptop and run (paste the token from the previous code block, same as for the portal):
```sh
az connectedk8s proxy --name k3s-site2 --resource-group rg-site2 --token $TOKEN
```

Open up another terminal on your laptop and run
```sh
kubectl get namespaces
```

As long as the Proxy is running you can now manage your cluster from your laptop, through Azure arc.

What happened with the deployments flux created?
```sh
kubectl get pods -n demo

NAME                                    READY   STATUS    RESTARTS   AGE
nginx-deployment-6fc69c57bd-htrbn       1/1     Running   0          148m
nginx-deployment-6fc69c57bd-nc6dc       1/1     Running   0          148m
nginx-deployment-6fc69c57bd-rbl82       1/1     Running   0          148m
nginx-deployment-nores-96b9d695-5m84c   1/1     Running   0          148m
nginx-deployment-nores-96b9d695-k8lvv   1/1     Running   0          148m
nginx-deployment-nores-96b9d695-l9lh9   1/1     Running   0          148m
```

Why are the nginx-deployment-nores pods running when we have a policy that's supposed to block pods without resource request/limits set?

Because the gatekeeper wasn't launched before we enabled Flux.

Delete all pods in namespace demo to verify that only pods with correct resources are created:
```sh
kubectl delete pods -n demo --all

kubectl get pods -n demo
```

We only have pods with resources correctly specified running in the namespace.
Also check the deployments:
```sh
kubectl get deployments -n demo

NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment         3/3     3            3           68s
nginx-deployment-nores   0/3     0            0           68s
```

Azure policy is controlling the behaviour within the cluster through gatekeeper functionality.

# 3
Create Lab server 2

Run from laptop

```sh
./create-vm.sh rg-site2 vm-host2
```


## Run from vm-host2
Install K3s

```sh
sudo ./install-k3s.sh
```

### Install Azure cli

```sh
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  

az login -i
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt
```

### Enable ARC on k3s cluster
```sh
export k3s_cluster_name="k3s-site2"
export resource_group="rg-site2"
export location="swedencentral"
alias k=kubectl
sudo chmod 755 /etc/rancher/k3s/k3s.yaml

az connectedk8s connect --name "$k3s_cluster_name" --resource-group "$resource_group" --location "$location" --kube-config ~/.kube/config
```

### Setup Flux
```sh
# Enable Flux extension on Arc-enabled cluster
az k8s-extension create \
  --cluster-name "$k3s_cluster_name" \
  --resource-group "$resource_group" \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux \
  --name flux

# Create Flux configuration to sync application from GitHub
az k8s-configuration flux create \
  --cluster-name "$k3s_cluster_name" \
  --resource-group "$resource_group" \
  --cluster-type connectedClusters \
  --name flux-config \
  --namespace flux-system \
  --scope cluster \
  --url https://github.com/johankardell/k3sdemo \
  --branch main \
  --kustomization name=flux path=./flux prune=true
```

### Enable Azure RBAC
Run from your laptop, and copy the output:
```sh
az ad signed-in-user show --query userPrincipalName -o tsv
```

For this lab, we're only allowing the current user. This could also be a group. [Microsoft Learn link](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/cluster-connect?tabs=azure-cli#microsoft-entra-authentication-option)

Run from vm-host2
```sh
AAD_ENTITY_ID=<paste from laptop output>
kubectl create clusterrolebinding demo-user-binding --clusterrole cluster-admin --user=$AAD_ENTITY_ID
```

You can now browse the cluster resources from the Azure portal, without pasting a token.

Run from laptop:
```sh
az connectedk8s proxy --name k3s-site2 --resource-group rg-site2
```

Run from laptop in new shell:
```sh
kubectl get namespaces
```
As long as the proxy is running you can now use kubectl from your laptop to manage your k3s cluster.

## Kubernetes Fleet Manager

Use the portal to:
1. Create a Kubernetes fleet
2. Add the two clusters we have created here to the fleet

Unfortunately there's not much functionality available for Arc enabled clusters in the fleet (right now), except listing them with current Kubernetes version. It's mainly a way of keeping track of clusters.

## Logging and Metrics

Use the portal to:
1. Enable Prometheus, with free Grafana visualizations
2. Enable Container insights (using Log analytics - this can become expensinve in large installations)

Do this for both clusters, and make sure you use the same Azure monitor workspace and Log analytics workspace for both clusters.

Bonus:
Enable managed Grafana through the portal. This is not a free service.

