# Recipe 1: Github, VSTS and Kubernetes

CI/CD pipeline between Github, Microsoft's Visual Studio for Teams \(VSTS\) and Kubernetes.

![CI/CD Architecture](images/cicd-architecture.png)

## Audience

The target audience for this tutorial is anyone looking for a Continuous Integration/Continuous Delivery pipeline solution using Github, VSTS and Kubernetes as the deployment platform. This  
is a step-by-step approach with many details on how things get connected together.

## Prerequisites

For this pipeline, you will need:

* A [Github](https://github.com/) account
* An [Azure](https://azure.microsoft.com/) account
* A Visual Studio for Teams (VSTS) account at [visualstudio.com](https://www.visualstudio.com)

## Solution Details

This guide will walk you through the process of creating a Continuous Integration/Continuous Delivery pipeline \(CI/CD pipeline\).

## Table of Contents

### Understanding the components of our infrastructure

| Components | Role | Notes 
| --- | --- | --- 
| Github | Source code Version Control System | Our Dockerfile and the Kubernetes services and deployment file will also be hosted here. 
| VSTS | Build docker images, Push docker images to the repo and deploy to Kubernetes | Azure Container Registry will the the repository for the images. You could also change this here and use dockerhub.  
| Kubernetes | Run the application | Kubernetes will run on Azure Container Services \(AKS\)

Our flow will be:

1. Code is pushed to Github
1. A Webhook is sent from Github to VSTS.
1. Based on the reception of the Webhook, VSTS will fetch the `Dockerfile` from the repository on Github and run a build image action.
1. A new Docker image of our code will be pushed to our Azure Container Registry repository.
1. VSTS will deploy the our workload based on the instruction from the `azure_visualizer-deployment.yml` file found under our repository.
1. Finaly, VSTS will will deploy a services object following the `azure_visualizer-svc.yml` file.

## Basic building blocks

In order to deploy the pipeline, we need to have in place a few components. The following steps will setup Kubernetes and the Azure Container Registry.

## Basic setup - Do this before proceeding

The first thing you should do is to clone this repo as most of the examples here will do relative reference to files.

```bash
git clone https://github.com/dcasati/k8s-training.git
```

With that out of the way, we let's define some global variables. They will be used throughout the labs.

1. Create the variables file

    ```bash
    # The name of our demo
    export demoname=k8s-demo
    cat << EOF > variables.rc
   
    # Enter here the email attached to your Azure subscription
    export myEmail=YOUR_EMAIL_HERE
   
    # The data center and resource name for your resources
    export resourcegroupname=${demoname}-rg
    
    # select a region to deploy your resources
    export location=eastus
    
    # Azure Container Registry
    export acrname=${demoname/-/}acr${RANDOM}

    # Kubernetes
    export clustername=$demoname-cluster
    EOF
    ```

1. source it to load the values

    ```bash
   source variables.rc
    ```
1. With these values, we can now create a Resource Group that will be used during our exercises.

    ```bash
    az group create \
        --name $demoname \
        --resource-group $resourcegroupname \
        --location $location
    ```

### Setting up Kubernetes

Here we will see the steps needed to setup a Kubernetes cluster on Azure.

> NOTE: At the time of this writing, Azure Container Services is in preview so before you can use it you will have to add that feature to your subscription with the following command:
    
```bash
az provider register -n Microsoft.ContainerService
```

## Procedure

1. Create an AKS instance

    ```bash
    az aks create \
        --resource-group $resourcegroupname \
        --name $clustername \
        --node-count 2 \
        --generate-ssh-keys \
        --kubernetes-version 1.8.1
    ```
    After a few minutes you should have you cluster up and running.

1. To install kubectl

    ```bash
    az aks install-cli
    ```
    > NOTE: This procedure will work on MacOS, Linux and Windows.

1. Run the following az command:

    ```bash
    az aks get-credentials \
    --resource-group $resourcegroupname \
    --name $clustername
    ```
    This will get the `KUBECONFIG` so you can later use with kubectl

1. To test your new setup, let's get the information about the PODs and Nodes.

    ```bash
    kubectl get nodes
    ```
### Create a container repository on Azure Container Registry

In this section, we will setup our private registry on Azure Container Registry.

1. Create an ACR instance

    ```bash
    az acr create \
        --resource-group $resourcegroupname \
        --name $acrname \
        --sku Basic
    ```

1. Save the value of the `loginServer` to a variable of the same name ($loginServer).
    
    ```bash
    loginServer=$(az acr list --resource-group $resourcegroupname --query "[].{acrLoginServer:loginServer}" --output tsv)
    ```

1. Enable admin access to ACR

    ```bash
    az acr update --name $acrname --admin-enabled true
    ```
1. Retrieve the credentials for the registry

    ```bash
    acrUsername=$(az acr credential show --resource-group $resourcegroupname --name $acrname --query username -o tsv)
    acrPassword=$(az acr credential show --resource-group $resourcegroupname --name $acrname --query passwords -o tsv | awk '/password\t/{print $2}')
    ```
1. Create the Secret to hold the ACR credentials
    ```bash
    kubectl create secret docker-registry myregistrykey \
        --docker-server $loginServer \
        --docker-username $acrUsername \
        --docker-password $acrPassword  \
        --docker-email $myEmail
    ```
## Creating the Continuous Integration

In the first part of this tutorial, we will create the mechanism for the Continuous Integration. Essentially, our code will live on Github and whenever there's a change to this code \(e.g.: a developer commits changes to the repo\) we will setup a Webhook that will trigger an action, informing VSTS of these changes. Once informed by Github, VSTS will act based on the rules we will setup soon.

## Configuring Github

For this example, fork the code available at: [https://github.com/dcasati/azure\_visualizer.git](https://github.com/dcasati/azure_visualizer.git)

## Configuring VSTS

1. Visit [VSTS](app.vssps.visualstudio.com/)
1. Sign in or create an account
1. Click an account (or use an existing one) and then create a new project

### Setting up the Continuous Integration on VSTS

1. Click on the Build button then on **+New definition**

    ![Create a new definition](images/vsts-1.png)

1. Next, on the `Select a template` screen, choose **start with an Empty process**.

    ![select a template](images/vsts-2.png)

1. Click on `Get sources` then select **Github** from the sources available on the right side.

    ![select Github](images/vsts-3.png)

1. Authorize the Github connection, then select the repository where you've forked the `azure_visualizer` code and the branch that will be used. Finally, under the `Clean` option, select **false**.

    ![configure the Github source](images/vsts-4.png)

1. Click on the `Save and queue` icon and then select `Save`.

1. Click on the `Triggers` tab, then select your Github repository on the left side of the screen. Finally, click on the `Enable Continuos Integration` box on the right side.

    ![Enable CI](images/vsts-ci.png)

1. Click on the `Save and queue` icon and then select `Save`.

With the initial connection to Github in place we will now configure the components that will build and publish the Docker image.

### Setting up the build process for the Docker image

1. Next, on the left side of the screen, click on `Process`. Name the Process with something meaningful such as `azure_visualizer_pipeline-CI`. Under the `Agent queue`, select **Hosted Linux Preview**.

    ![select a Linux host](images/vsts-LinuxHost.png)

1. Add a task to the phase by clicking on the plus sign.

    ![add a new task](images/vsts-6.png)

1. On the `Add tasks blade` search for `docker` then click on `Add`. While here, go ahead and click on `Add` one more time. We will use the Docker integration when building and then when pushing the image to the repository.

    ![add docker](images/vsts-7.png)

1. Name the first docker task as `Build an image`. Select **Azure Container Registry** as the `Container Registry Type` and then select an appropriate Azure subscription.

    ![configure the registry](images/vsts-8.png)

    In my case, you can see that the registry `casatix` was choosen and that the `Docker File` was set to `/**Dockerfile`. Click on `Save and queue` then on `Save`. Select **Build image** under the `Action` section.

    > Note: `/**Dockerfile` should correspond to the Dockerfile on your Github repo. If you have forked our code example, than you are good to go. If you are adapting this tutorial to your use case, make sure that you map this option correctly otherwise you will not be able to build an image.

    ![choose the dockerfile](images/vsts-9.png)

1. Click on the second Docker task and name that `Push images`. Like the previous step, choose the appropriate `Container Registry Type`, `Azure subscription` and the `Azure Container Registry`.

    ![configure the task](images/vsts-10.png)

1. Finaly, select **Push images** under the `Action` section.

    ![push the image](images/vsts-11.png)

1. Select `Include Latest Tag`

    ![include the latest tag](images/vsts-12.png)

1. Click on `Save and queue` then on `Save`.

### Setting up the Continuous Delivery on VSTS

Name this as `Phase 2 - Continuous Delivery`

![phase 2](images/vsts-13.png)

1. Click on the plus sign in front of the `Phase 2` and select to add a new task. Filter the task for `kubernetes` then click on `Add`. Do this step one more time as we will need two Kubernetes tasks, one for the deployment and another for the sevice.

    ![phase 2](images/vsts-14.png)

1. Name this first task `Create Kubernetes Deployment`,

| Item | Value |
| --- | --- |
| Display name | Create Kubernetes Deployment |
| Kubernetes Service Connection | Paste your KUBECONFIG here\* |
| Container Registry type | Azure Container Registry |

### Getting the KUBECONFIG from AKS

You will need to retrieve your KUBECONFIG for the `Kubernetes Services Connection`. To get this file, execute the following:

```bash
az aks get-credentials \
    -g $resourcegroupname \
    -n $clustername \
    -f myk8s_cluster.conf
```

![phase 2](images/vsts-15.png)

Scroll down the `Commands` section and select **create** under `Command` dropdown menu. Select the `Use Configuration files` option. Then under the  `Configuration File` click on the button button to select the deployment file \(`azure_visualizer-deployment.yml` in the picture\).

> Note: This file is hosted on your Github repository.

Click on `Save and Queue` then on `Save`.

![phase 2](images/vsts-16.png)

Repeat the previous step for the the next Kubernetes task with the following values:

| Item | Value |
| --- | --- |
| Display name | Create Kubernetes Service |
| Kubernetes Service Connection | Select the Kubernetes connection from the dropdown menu |
| Container Registry type | Azure Container Registry |
| Azure Container Registry | casatix\* |

> \* Modify this value to reflect your setup.

Commands

| Item | Value |  
| --- | --- |  
| Command | create |  
| Configuration File | azure_visualizer-svc.yml |

Click on `Save and Queue` then on `Save`.

## Checking the deployment

You can verify if the deployment was successful by running the following:

```bash
$ kubectl get pods -l k8s-app=azure-visualizer
NAME                                READY     STATUS    RESTARTS   AGE
azure-visualizer-1640327816-t8f3g   1/1       Running   0          10d
```