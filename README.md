# K3S LAB

## Pre-reqs
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
Assign the Azure policy 'Kubernetes cluster containers CPU and memory resource requests must be defined' to the subscription of the lab. Set the parameter namespaces to "demo". This way we won't break Defender for containers and other pods that might spin up in other namespaces.

This policy will block the creation of pods without resource request defined.

## Lab server 1
In this lab we're creating an Azure VM running Ubuntu that we will use a simulated edge server running in for example a warehouse, store or factory.

**Run from laptop:**

```sh
# Create resource group rg-site1 with Azure VM vm-host1
./create-vm.sh rg-site1 vm-host1
```

**Run from vm-host1**

```sh
# Install K3s
sudo ./install-k3s.sh

# Install Azure cli
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  

# Login and setup
az login -i
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt
```

### Enable ARC on k3s cluster

ARC will allow us to extend cloud functionality to our edge servers and clusters. In this lab we are only Arc enabling our K3s installation, since the VM already lives in Azure. If this was a real scenario we would also Arc enable the server.

**Run from vm-host1**
```sh
export k3s_cluster_name="k3s-site1"
export resource_group="rg-site1"
export location="swedencentral"
alias k=kubectl
sudo chmod 755 /etc/rancher/k3s/k3s.yaml

az connectedk8s connect --name "$k3s_cluster_name" --resource-group "$resource_group" --location "$location" --kube-config ~/.kube/config

```

### Setup Flux

Flux is the Gitops engine currently supported from Microsoft. We will install it as an extension on the k3s cluster. Flux will also become visible in the Azure portal, and we can also perform operations from the portal through Flux.

In this step we are also adding a configuration for Flux to let it pull manifests from this repo and automatically apply them to the K3s cluster.

Spend a minute or two and look through the [manifests](https://github.com/johankardell/k3sdemo) while Flux is installing. Notice the difference between the two different nginx-deployments.

**Run from vm-host1**
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
If you look at the Arc enabled K3s cluster in the Azure portal right now, and click on for example Namespaces - you will be asked to provide a token. In this step we will create that token. This is one of the two different ways we can access our cluster through the portal.

**Run from vm-host1**
```sh
kubectl create serviceaccount azure-user -n default
kubectl create clusterrolebinding azure-user-binding --clusterrole cluster-admin --serviceaccount default:azure-user

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: azure-user-secret
  annotations:
    kubernetes.io/service-account.name: azure-user
type: kubernetes.io/service-account-token
EOF

TOKEN=$(kubectl get secret azure-user-secret -o jsonpath='{$.data.token}' | base64 -d | sed 's/$/\n/g')

echo Paste this into the Azure portal: $TOKEN
```

### Use kubectl from your laptop
Open a terminal on your laptop and run (paste the token from the previous code block, same as for the portal):
```sh
az connectedk8s proxy --name k3s-site2 --resource-group rg-site2 --token <paste token from previous code block>
```

Open up another terminal on your laptop and run
```sh
kubectl get namespaces
```

As long as the Proxy is running you can now manage your cluster from your laptop, through Azure arc.

### Azure policy on Arc enabled clusters

We started out assigning an Azure policy to the subscription that we're using. Did it work?  
What did it do?
Let's investigate.

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

Because Gatekeeper didn't launch before we enabled Flux.

Delete all pods in namespace demo to verify that only pods with correct resources are created.

**Run from laptop**
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

Azure policy is controlling the behaviour within the cluster through gatekeeper functionality. This is of course a problem, since the Flux config always will be _non-compliant_ as long as we have this misconfiguration.

# Create Lab server 2

**Run from laptop**

```sh
./create-vm.sh rg-site2 vm-host2
```

**Run from vm-host2**

```sh
# Install K3s
sudo ./install-k3s.sh

#Install Azure cli
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  

# Login and setup
az login -i
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt
```

### Enable ARC on k3s cluster

**Run from vm-host2**
```sh
export k3s_cluster_name="k3s-site2"
export resource_group="rg-site2"
export location="swedencentral"
alias k=kubectl
sudo chmod 755 /etc/rancher/k3s/k3s.yaml

az connectedk8s connect --name "$k3s_cluster_name" --resource-group "$resource_group" --location "$location" --kube-config ~/.kube/config
```

### Setup Flux
**Run from vm-host2**

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
In the first lab we copied a service account token and used it to gain access to the cluster. This can work, but is a very cumbersome way to work at scale. Another way - perhaps a better way - is to enable Azure RBAC for your cluster. This will allow us to access the cluster without pasting a token. We will also automatically get access to the cluster through the Azure portal. 

**Run from your laptop**, and copy the output:
```sh
az ad signed-in-user show --query userPrincipalName -o tsv
```

For this lab, we're only allowing the current user. This could also be a group. [Microsoft Learn link](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/cluster-connect?tabs=azure-cli#microsoft-entra-authentication-option)

**Run from vm-host2**
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

**Bonus:** Enable managed Grafana through the portal. This is not a free service, but for a lab the cost is a dollar or two.

Look at the visualizations and pre-built dashboards available in the Azure portal. They will only show data for the selected cluster, but if you do the bonus challenge you can get dashboards covering multiple clusters.

Open Logs for one of the K3s clusters through the Azure portal. Search for a pre-built KQL query named "Kubernetes events". Run it and familiarize yourself with the syntax and output.  
Practice sorting the logs and filter the logs per cluster.  
Can you find the logs from the deployment that failed because of the Azure policy?

### Bonus challenges
* Defender for containers
* Create Azure container registry and enable Defender for containers on it
* Create a new git repo, with your own manifests
* Create a new Flux configuration that pulls from your git repo
