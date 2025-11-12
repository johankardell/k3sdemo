#!/bin/bash

# List of subscription names or IDs
subscriptions=("one" "two" "three" "four" "five")

# Resource providers to register
providers=(
    "Microsoft.Kubernetes"
    "Microsoft.KubernetesConfiguration"
    "Microsoft.ExtendedLocation"
)

# Loop through subscriptions
for sub in "${subscriptions[@]}"; do
    echo "Switching to subscription: $sub"
    az account set --subscription "$sub"

    # Register each provider
    for provider in "${providers[@]}"; do
        echo "Registering provider: $provider in subscription: $sub"
        az provider register --namespace "$provider"
    done
done

echo "✅ All providers registered successfully across subscriptions."
