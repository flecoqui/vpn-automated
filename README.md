# Deploying an Azure Key Vault, Azure Storage Account and Azure Container Registry with VPN

## Introduction

This document describes how to deploy Azure Key Vault, Azure Storage Account and Azure Container Registry:
- with public access
- with private access through a VPN gateway

- One configuration with public endpoints to reach Key Vault, Storage and Registry.

![Public Infrastructure](./diagrams/public-vpn.png)

- One configuration with private endpoints to reach Key Vault, Storage and Registry.

![Private Infrastructure](./diagrams/private-vpn.png)


## Getting Started

In this repository, you'll find scripts and bicep files to deploy a Azure Key Vault, Azure Storage Account and Azure Container Registry
- with public access Infrastructure,
- with private access Infrastructure. 

This chapter describes how to :

1. Install the pre-requisites including Visual Studio Code, Dev Container
2. Create, deploy the infrastructure

This repository contains the following resources :

- A Dev container under '.devcontainer' folder
- The Azure configuration for a deployment under '.config' folder
- The scripts, bicep files and dataset files used to deploy the infrastructure under: ./infra

### Installing the pre-requisites

In order to test the solution, you need first an Azure Subscription, you can get further information about Azure Subscription [here](https://azure.microsoft.com/en-us/free).

You also need to install Git client and Visual Studio Code on your machine, below the links.

|[![Windows](./diagrams/windows_logo.png)](https://git-scm.com/download/win) |[![Linux](./diagrams/linux_logo.png)](https://git-scm.com/download/linux)|[![MacOS](./diagrams/macos_logo.png)](https://git-scm.com/download/mac)|
|:---|:---|:---|
| [Git Client for Windows](https://git-scm.com/download/win) | [Git client for Linux](https://git-scm.com/download/linux)| [Git Client for MacOs](https://git-scm.com/download/mac) |
[Visual Studio Code for Windows](https://code.visualstudio.com/Download)  | [Visual Studio Code for Linux](https://code.visualstudio.com/Download)  &nbsp;| [Visual Studio Code for MacOS](https://code.visualstudio.com/Download) &nbsp; &nbsp;|

Once the Git client is installed you can clone the repository on your machine running the following commands:

1. Create a Git directory on your machine

    ```bash
        c:\> mkdir git
        c:\> cd git
        c:\git>
    ```

2. Clone the repository.
    For instance:

    ```bash
        c:\git> git clone  https://github.com/flecoqui/vpn-automated.git
        c:\git> cd ./vpn-automated
        c:\git\vpn-automated>
    ```

### Using Dev Container

#### Installing Dev Container pre-requisites

You need to install the following pre-requisite on your machine

1. Install and configure [Docker](https://www.docker.com/get-started) for your operating system.

   - Windows / macOS:

     1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop) for Windows/Mac.

     2. Right-click on the Docker task bar item, select Settings / Preferences and update Resources > File Sharing with any locations your source code is kept. See [tips and tricks](https://code.visualstudio.com/docs/remote/troubleshooting#_container-tips) for troubleshooting.

     3. If you are using WSL 2 on Windows, to enable the [Windows WSL 2 back-end](https://docs.docker.com/docker-for-windows/wsl/): Right-click on the Docker taskbar item and select Settings. Check Use the WSL 2 based engine and verify your distribution is enabled under Resources > WSL Integration.

   - Linux:

     1. Follow the official install [instructions for Docker CE/EE for your distribution](https://docs.docker.com/get-docker/). If you are using Docker Compose, follow the [Docker Compose directions](https://docs.docker.com/compose/install/) as well.

     2. Add your user to the docker group by using a terminal to run: 'sudo usermod -aG docker $USER'

     3. Sign out and back in again so your changes take effect.

2. Ensure [Visual Studio Code](https://code.visualstudio.com/) is already installed.

3. Install the [Remote Development extension pack](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack)

#### Using Visual Studio Code and Dev Container

1. Launch Visual Studio Code in the folder where you cloned the 'ps-data-foundation-imv' repository

    ```bash
        c:\git\dataops> code .
    ```

2. Once Visual Studio Code is launched, you should see the following dialog box:

    ![Visual Studio Code](./diagrams/reopen-in-container.png)

3. Click on the button 'Reopen in Container'
4. Visual Studio Code opens the Dev Container. If it's the first time you open the project in container mode, it first builds the container, it can take several minutes to build the new container.
5. Once the container is loaded, you can open a new terminal (Terminal -> New Terminal).
6. And from the terminal, you have access to the tools installed in the Dev Container like az client,....

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ az login
    ```

### How to deploy infrastructure from the Dev Container terminal

The Dev Container is now running, you can use the bash file [./infra/deploy-infra.sh ](./infra/infra/deploy-infra.sh ) to:

- deploy the infrastructure 
- create data copy pipeline

Below the list of arguments associated with 'deploy-infra.sh ':

- -a  Sets action {azure-login, deploy-public-vpn, remove-public-vpn, deploy-private-vpn, remove-private-vpn}
- -c  Sets the configuration file
- -e  Sets environment dev, staging, test, preprod, prod
- -t  Sets deployment Azure Tenant Id
- -s  Sets deployment Azure Subscription Id
- -r  Sets the Azure Region for the deployment

#### Connection to Azure

Follow the steps below to establish with your Azure Subscription where you want to deploy your infrastructure.

1. Launch the Azure login process using 'deploy-infra.sh -a azure-login'.
Usually this step is not required in a pipeline as the connection with Azure is already established.

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh   -a azure-login
    ```

    After this step the default Azure subscription has been selected. You can still change the Azure subscription, using Azure CLI command below:

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ az account set --subscription <azure-subscription-id>
    ```
    Using the command below you can define the Azure region, subscription, the tenant and the environment where Azure Key Vault, Azure Storage Account and Azure Container Registry will be deployed.

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh -a azure-login -r <azure_region> -e dev -s <subscription_id> -t <tenant_id>
    ```

    After this step, the variables AZURE_REGION, AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID and AZURE_ENVIRONMENT used for the deployment are stored in the file ./.config/.default.env.
    The variable AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP is by default empty string.
    By default the name of the resource group will be 'rgvpn[AZURE_ENVIRONMENT][visibility][AZURE_SUFFIX]'
    where [visibility] value is 'pri' for private deployment and 'pub' for public deployment.

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ cat ./.config/.default.env
        AZURE_REGION=westus3
        AZURE_SUFFIX=to-be-updated (4 digits)
        AZURE_SUBSCRIPTION_ID=to-be-updated
        AZURE_TENANT_ID=to-be-updated
        AZURE_ENVIRONMENT=dev
        AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP=""
    ```

    In order to deploy the infrastructure with the script 'deploy-infra.sh ', you need to be connected to Azure with sufficient privileges to assign roles to Azure Key Vault and Azure Storage Accounts.
    Instead of using an interactive authentication session with Azure using your Azure account, you can use a service principal connection.

    If you don't have enough permission to create the resource groups for this deployment and you must reuse existing resource groups, you can set the value AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP in file ./.config/.default.env.

    For instance:

    ```bash
        AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP="vpn-test-rg"
    ```

    If you don't have enough permission to deploy some resources in your subscription and you must reuse existing resources like Azure Key Vault, Azure Storage and Azure Container Registry, you can change the file [naming-convention.bicep](./bicep/naming-convention.bicep) to set the name of some resources.

    For instance:
    ```bash
        @description('The Azure Environment (dev, staging, preprod, prod,...)')
        @maxLength(13)
        param environment string = uniqueString(resourceGroup().id)

        @description('The cloud visibility (pub, pri)')
        @maxLength(7)
        param visibility string = 'pub'

        @description('The Azure suffix')
        @maxLength(4)
        param suffix string = '0000'


        var baseName = toLower('${environment}${visibility}${suffix}')

        output acrName string = 'acr${baseName}'
        output appInsightsName string = 'appi${baseName}'
        output vnetName string = 'vnet${baseName}'
        output storageAccountName string = 'st${baseName}'
        output storageAccountDefaultContainerName string = 'test${baseName}'
        output keyVaultName string = 'kv${baseName}'
        output privateEndpointSubnetName string = 'snet${baseName}pe'
        output datagwSubnetName string = 'snet${baseName}dtgw'
        output vpnGatewayName string = 'vnetvpngateway${baseName}'
        output vpnGatewayPublicIpName string = 'vnetvpngatewaypip${baseName}'
        output dnsResolverName string = 'vnetdnsresolver${baseName}'
        output bastionSubnetName string = 'AzureBastionSubnet'
        output bastionHostName string = 'bastion${baseName}'
        output bastionPublicIpName string = 'bastionpip${baseName}'
        output gatewaySubnetName string = 'GatewaySubnet'
        output dnsDelegationSubNetName string = 'DNSDelegationSubnet'
        output baseName string = baseName
        output resourceGroupAzureAIName string = 'rgvpn${baseName}'
    ```

#### Deploying Azure Key Vault, Azure Storage Account and Azure Container Registry with public endpoint

1. Once you are connected to your Azure subscription, you can now deploy an Azure Key Vault, Azure Storage Account and Azure Container Registry infrastructure associated with public endpoints.

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh   -a deploy-public-vpn
    ```

    After this step, the variables AZURE_SUFFIX used for the deployment are stored in the file ./.config/.default.env.
    AZURE_SUFFIX is used to name the Azure resource. For a public endpoint deployement with suffix will be "${AZURE_ENVIRONMENT}pub${AZURE_SUFFIX}", and "${AZURE_ENVIRONMENT}pri${AZURE_SUFFIX}" for a deployment with private endpoints
   

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ cat ./.default.env
        AZURE_REGION=westus3
        AZURE_SUBSCRIPTION_ID=to-be-completed
        AZURE_TENANT_ID=to-be-completed
        AZURE_ENVIRONMENT=dev
        AZURE_SUFFIX=3033
    ```

    AZURE_REGION defines the Azure region where you want to install your infrastructure, it's 'westus3' by default.
    AZURE_SUFFIX defines the suffix which is used to name the Azure resources. By default this suffix includes 4 random digits which are used to avoid naming conflict when a resource with the same name has already been deployed in another subscription.
    AZURE_SUBSCRIPTION_ID is the Azure Subscription Id where you want to install your infrastructure
    AZURE_TENANT_ID is the Azure Tenant Id used for the authentication.
    AZURE_ENVIRONMENT defines the environment 'dev', 'stag', 'prod',...


2. Once Azure Key Vault, Azure Storage Account and Azure Container Registry are deployed into your Azure subscription, you can check whether all the associated resources are deployed with Azure Portal. 

##### Removing the public resources

1. When your tests are over, you can remove the infrastructure running the following commands:

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh   -a remove-public-vpn
    ```


#### Deploying Azure Key Vault, Azure Storage Account and Azure Container Registry with private endpoint

1. Once you are connected to your Azure subscription, you can now deploy an Azure Key Vault, Azure Storage Account and Azure Container Registry infrastructure associated with private endpoints.

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh   -a deploy-private-vpn
    ```

    After this step, the variables AZURE_SUFFIX and PURVIEW_PRINCIPAL_ID used for the deployment are stored in the file ./.config/.default.env.
    AZURE_SUFFIX is used to name the Azure resource. For a private endpoint deployement with suffix will be "${AZURE_ENVIRONMENT}pub${AZURE_SUFFIX}", and "${AZURE_ENVIRONMENT}pri${AZURE_SUFFIX}" for a deployment with private endpoints

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ cat ./.config/.default.env
        AZURE_REGION=westus3
        AZURE_SUBSCRIPTION_ID=to-be-completed
        AZURE_TENANT_ID=to-be-completed
        AZURE_ENVIRONMENT=dev
        AZURE_SUFFIX=3033
    ```

    AZURE_REGION defines the Azure region where you want to install your infrastructure, it's 'westus3' by default.
    AZURE_SUFFIX defines the suffix which is used to name the Azure resources. By default this suffix includes 4 random digits which are used to avoid naming conflict when a resource with the same name has already been deployed in another subscription.
    AZURE_SUBSCRIPTION_ID is the Azure Subscription Id where you want to install your infrastructure
    AZURE_TENANT_ID is the Azure Tenant Id used for the authentication.
    AZURE_ENVIRONMENT defines the environment 'dev', 'stag', 'prod',...


2. Once Azure Key Vault, Azure Storage Account and Azure Container Registry are deployed, the deployment script automatically:
   - Copies `install.sh` and `gen-client.sh` to the gateway VM over SSH
   - Runs `install.sh` to install and configure OpenVPN + BIND9 on the VM
   - Generates a client profile (`devcontainer`) via `gen-client.sh`
   - Downloads the ready-to-use profile to `./client.ovpn` in this repository

3. Connect to the VPN from the Dev Container terminal:

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ sudo openvpn --config client.ovpn
    ```

4. Once connected, run `configure-private-vpn` to test access to the private services:

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh   -a configure-private-vpn
    ```

##### Removing the private resources

1. When your tests are over, you can remove the infrastructure running the following commands:

    ```bash
        vscode ➜ /workspaces/vpn-automated (main) $ ./infra/deploy-infra.sh   -a remove-private-vpn
    ```
