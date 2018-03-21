#!/usr/bin/env  bash
source variables.rc

az group create \
        --name $demoname \
        --resource-group $resourcegroupname \
        --location $location

az provider register -n Microsoft.ContainerService

echo "Creating AKS Cluster"
az aks create \
    --resource-group $resourcegroupname \
    --name $clustername \
    --node-count 2 \
    --generate-ssh-keys \
    --kubernetes-version 1.8.1

echo "Getting AKS credentials for " $clustername
az aks get-credentials \
    --resource-group $resourcegroupname \
    --name $clustername

echo "Creating ACR instance"
az acr create \
    --resource-group $resourcegroupname \
    --name $acrname \
    --sku Basic

loginServer=$(az acr list --resource-group $resourcegroupname --query "[].{acrLoginServer:loginServer}" --output tsv)

az acr update --name $acrname --admin-enabled true

acrUsername=$(az acr credential show --resource-group $resourcegroupname --name $acrname --query username -o tsv)
acrPassword=$(az acr credential show --resource-group $resourcegroupname --name $acrname --query passwords -o tsv | awk '/password\t/{print $2}')

kubectl create secret docker-registry myregistrykey \
    --docker-server $loginServer \
    --docker-username $acrUsername \
    --docker-password $acrPassword  \
    --docker-email $myEmail