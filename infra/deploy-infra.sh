#!/bin/sh
##########################################################################################################################################################################################
#- Purpose: Script used to install pre-requisites, deploy/undeploy service, start/stop service, test service
#- Parameters are:
#- [-a] ACTION - value: azure-login, deploy-public-vpn, deploy-private-vpn, configure-private-vpn,remove-public-vpn, remove-private-vpn
#- [-e] environment - "dev", "stag", "preprod", "prod"
#- [-c] Sets the configuration file
#- [-t] Sets deployment Azure Tenant Id
#- [-s] Sets deployment Azure Subcription Id
#- [-r] Sets the Azure Region for the deployment#
# if [ -z "$BASH_VERSION" ]
# then
#    echo Force bash
#    exec bash "$0" "$@"
# fi
# executable
###########################################################################################################################################################################################
set -u
# echo  "$0" "$@"
BASH_SCRIPT=$(readlink -f "$0")
# Get the directory where the bash script is located
SCRIPTS_DIRECTORY=$(dirname "$BASH_SCRIPT")



##############################################################################
# colors for formatting the output
##############################################################################
# shellcheck disable=SC2034
{
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color
}
##############################################################################
#- function used to check whether an error occurred
##############################################################################
checkError() {
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "${RED}"
        echo "An error occurred exiting from the current bash${NC}"
        exit 1
    fi
}
##############################################################################
#- print functions
##############################################################################
printMessage(){
    echo "${GREEN}$1${NC}"
}
printWarning(){
    echo "${YELLOW}$1${NC}"
}
printError(){
    echo "${RED}$1${NC}"
}
printProgress(){
    echo "${BLUE}$1${NC}"
}
#######################################################
#- used to print out script usage
#######################################################
usage() {
    echo
    echo "Arguments:"
    printf " -a  Sets deploy-infra ACTION { azure-login, deploy-public-vpn, deploy-private-vpn, configure-private-vpn,remove-public-vpn, remove-private-vpn }\n"
    printf " -e  Sets the environment - by default 'dev' ('dev', 'test', 'stag', 'prep', 'prod')\n"
    printf " -s  Sets subscription id \n"
    printf " -t  Sets tenant id\n"
    printf " -c  Sets the configuration file\n"
    printf " -r  Sets the Azure Region for the deployment\n"
    echo
    echo "Example:"
    printf " bash ./deploy-infra.sh -a deploy-public-vpn \n"
}
##############################################################################
#- readConfigurationFile: Update configuration file
#  arg 1: Configuration file path
##############################################################################
readConfigurationFile(){
    file="$1"

    set -o allexport
    # shellcheck disable=SC1090
    . "$file"
    set +o allexport
}
##############################################################################
#- readConfigurationFileValue: Read one value in  configuration file
#  arg 1: Configuration file path
#  arg 2: Variable Name
##############################################################################
readConfigurationFileValue(){
    configFile="$1"
    variable="$2"

    grep "${variable}=*"  < "${configFile}" | head -n 1 | sed "s/${variable}=//g"
}
##############################################################################
#- updateConfigurationFile: Update configuration file
#  arg 1: Configuration file path
#  arg 2: Variable Name
#  arg 3: Value
##############################################################################
updateConfigurationFile(){
    configFile="$1"
    variable="$2"
    value="$3"

    count=$(grep "${variable}=.*" -c < "$configFile") || true
    if [ "${count}" != 0 ]; then
        ESCAPED_REPLACE=$(printf '%s\n' "${value}" | sed -e 's/[\/&]/\\&/g')
        sed -i "s/${variable}=.*/${variable}=${ESCAPED_REPLACE}/g" "${configFile}"  2>/dev/null
    elif [ "${count}" = 0 ]; then
        # shellcheck disable=SC2046
        if [ $(tail -c1 "${configFile}" | wc -l) -eq 0 ]; then
            echo "" >> "${configFile}"
        fi
        echo "${variable}=${value}" >> "${configFile}"
    fi
    printProgress "${variable}=${value}"
}
##############################################################################
#- Read deployment outputs from naming-convention Bicep template
#  arg 1: env
#  arg 2: visibility
#  arg 3: Suffix
#  arg 4: Resource Group Name
##############################################################################
setAzureResourceNames()
{
    env="$1"
    visibility="$2"
    suffix="$3"
    RG="$4"

    printProgress "Getting Azure resource names for env='$env' visibility='$visibility' suffix='$suffix' from bicep file: $SCRIPTS_DIRECTORY/bicep/naming-convention.bicep"
    DEPLOY_NAME=$(date +"naming-convention-%y%m%d%H%M%S")
    cmd="az deployment group create --name \"${DEPLOY_NAME}\" --resource-group \"${RG}\" --template-file $SCRIPTS_DIRECTORY/bicep/naming-convention.bicep --parameters suffix=\"${suffix}\" environment=\"${env}\" visibility=\"${visibility}\""
    # printProgress "$cmd"
    eval "$cmd" 2>/dev/null >/dev/null|| true
    checkError

    cmd="az deployment group show --name \"${DEPLOY_NAME}\" --resource-group \"${RG}\" --query properties.outputs"
    #printProgress "$cmd"
    RESULT=$(eval "$cmd")
    checkError
    printProgress "RESULT: $RESULT"

    AZURE_VNET_NAME=$(echo ${RESULT}  | jq -r '.vnetName.value' 2>/dev/null)
    echo "AZURE_VNET_NAME: $AZURE_VNET_NAME"
    AZURE_SUBNET_NAME=$(echo ${RESULT}  | jq -r '.privateEndpointSubnetName.value' 2>/dev/null)
    echo "AZURE_SUBNET_NAME: $AZURE_SUBNET_NAME"
    AZURE_DATAGW_SUBNET_NAME=$(echo ${RESULT}  | jq -r '.datagwSubnetName.value' 2>/dev/null)
    echo "AZURE_DATAGW_SUBNET_NAME: $AZURE_DATAGW_SUBNET_NAME"
    AZURE_GATEWAY_SUBNET_NAME=$(echo ${RESULT}  | jq -r '.gatewaySubnetName.value' 2>/dev/null)
    echo "AZURE_GATEWAY_SUBNET_NAME: $AZURE_GATEWAY_SUBNET_NAME"
    AZURE_DNS_DELEGATION_SUBNET_NAME=$(echo ${RESULT}  | jq -r '.dnsDelegationSubNetName.value' 2>/dev/null)
    echo "AZURE_DNS_DELEGATION_SUBNET_NAME: $AZURE_DNS_DELEGATION_SUBNET_NAME"

    AZURE_STORAGE_ACCOUNT_NAME=$(echo ${RESULT}  | jq -r '.storageAccountName.value' 2>/dev/null)
    echo "AZURE_STORAGE_ACCOUNT_NAME: $AZURE_STORAGE_ACCOUNT_NAME"

    AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME=$(echo ${RESULT}  | jq -r '.storageAccountDefaultContainerName.value' 2>/dev/null)
    echo "AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME: $AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME"    
    AZURE_KEY_VAULT_NAME=$(echo ${RESULT}  | jq -r '.keyVaultName.value' 2>/dev/null)
    echo "AZURE_KEY_VAULT_NAME: $AZURE_KEY_VAULT_NAME"


    AZURE_ACR_NAME=$(echo ${RESULT}  | jq -r '.acrName.value' 2>/dev/null)
    echo "AZURE_ACR_NAME: $AZURE_ACR_NAME"

    AZURE_APP_INSIGHTS_NAME=$(echo ${RESULT}  | jq -r '.appInsightsName.value' 2>/dev/null)
    echo "AZURE_APP_INSIGHTS_NAME: $AZURE_APP_INSIGHTS_NAME"

    AZURE_VPN_GATEWAY_PIP_NAME=$(echo ${RESULT}  | jq -r '.vpnGatewayPublicIpName.value' 2>/dev/null)
    echo "AZURE_VPN_GATEWAY_PIP_NAME: $AZURE_VPN_GATEWAY_PIP_NAME"
    AZURE_DNS_RESOLVER_NAME=$(echo ${RESULT}  | jq -r '.dnsResolverName.value' 2>/dev/null)
    echo "AZURE_DNS_RESOLVER_NAME: $AZURE_DNS_RESOLVER_NAME"

    AZURE_RESOURCE_GROUP_AZURE_AI_NAME=$(echo ${RESULT}  | jq -r '.resourceGroupName.value' 2>/dev/null)
    echo "AZURE_RESOURCE_GROUP_AZURE_AI_NAME: $AZURE_RESOURCE_GROUP_AZURE_AI_NAME"

}

##############################################################################
#- Read deployment outputs from Bicep template
#  arg 1: Deployment Name
#  arg 2: Resource Group Name
##############################################################################
readDeploymentOutputs()
{
    deployname="$1"
    RG="$2"

    cmd="az deployment group show --name \"${deployname}\" --resource-group \"${RG}\" --query properties.outputs"
    #printProgress "$cmd"
    RESULT=$(eval "$cmd")
    checkError
    printProgress "RESULT: $RESULT"
    AZURE_KEY_VAULT_NAME=$(echo ${RESULT}  | jq -r '.keyVaultName.value' 2>/dev/null)
    echo "AZURE_KEY_VAULT_NAME: $AZURE_KEY_VAULT_NAME"
    AZURE_KEY_VAULT_URI=$(echo ${RESULT}  | jq -r '.keyVaultUri.value' 2>/dev/null)
    echo "AZURE_KEY_VAULT_URI: $AZURE_KEY_VAULT_URI"
    
    AZURE_STORAGE_ACCOUNT_NAME=$(echo ${RESULT}  | jq -r '.storageAccountName.value' 2>/dev/null)
    echo "AZURE_STORAGE_ACCOUNT_NAME: $AZURE_STORAGE_ACCOUNT_NAME"   
    AZURE_STORAGE_BLOB_URI=$(echo ${RESULT}  | jq -r '.storageBlobUri.value' 2>/dev/null)
    echo "AZURE_STORAGE_BLOB_URI: $AZURE_STORAGE_BLOB_URI"
    AZURE_STORAGE_FILE_URI=$(echo ${RESULT}  | jq -r '.storageFileUri.value' 2>/dev/null)
    echo "AZURE_STORAGE_FILE_URI: $AZURE_STORAGE_FILE_URI"
    AZURE_STORAGE_DFS_URI=$(echo ${RESULT}  | jq -r '.storageDfsUri.value' 2>/dev/null)
    echo "AZURE_STORAGE_DFS_URI: $AZURE_STORAGE_DFS_URI"

    AZURE_ACR_NAME=$(echo ${RESULT}  | jq -r '.acrName.value' 2>/dev/null)
    echo "AZURE_ACR_NAME: $AZURE_ACR_NAME"
    AZURE_ACR_LOGIN_SERVER=$(echo ${RESULT}  | jq -r '.acrLoginServer.value' 2>/dev/null)
    echo "AZURE_ACR_LOGIN_SERVER: $AZURE_ACR_LOGIN_SERVER"

    AZURE_APP_INSIGHTS_NAME=$(echo ${RESULT}  | jq -r '.appInsightsName.value' 2>/dev/null)
    echo "AZURE_APP_INSIGHTS_NAME: $AZURE_APP_INSIGHTS_NAME"     
}

##############################################################################
#- Get Azure AI Resource Group Name
#  arg 1: Env
#  arg 2: Visibility
#  arg 3: Suffix
##############################################################################
getVPNResourceGroupName()
{
    env="$1"
    visibility="$2"
    suffix="$3"
    if [ ! -z "${AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP+x}" ] ; then
        if [ -z "${AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP}" ] && [ "${AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP}" != "" ] ; then
            echo "${AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP}"
            return
        fi
    fi
    if [ -z "${1+x}" ] ; then
        echo "rgvpndevpub"
    else
        echo "rgvpn${env}${visibility}${suffix}"
    fi
}

##############################################################################
#- Get Storage Account Name
#  arg 1: Env
#  arg 2: Visibility
#  arg 3: Suffix
##############################################################################
getStorageAccountName()
{
    env="$1"
    visibility="$2"
    suffix="$3"
    echo "st${env}${visibility}${suffix}"
}
##############################################################################
#- Get Key Vault Name
#  arg 1: Env
#  arg 2: Visibility
#  arg 3: Suffix
##############################################################################
getKeyVaultName()
{
    env="$1"
    visibility="$2"
    suffix="$3"
    echo "kv${env}${visibility}${suffix}"
}
##############################################################################
#- azure Login
##############################################################################
azLogin() {
    # Check if current process's user is logged on Azure
    if [ ! -z "${AZURE_SUBSCRIPTION_ID+x}" ] && [ ! -z "${AZURE_TENANT_ID+x}" ]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv 2> /dev/null) || true
        TENANT_ID=$(az account show --query tenantId -o tsv 2> /dev/null) || true
        if [ "$AZURE_SUBSCRIPTION_ID" = "$SUBSCRIPTION_ID" ] && [ "$AZURE_TENANT_ID" = "$TENANT_ID" ]; then
            printMessage "Already logged in Azure CLI"
            return
        fi
    fi
    if [ ! -z "${AZURE_TENANT_ID+x}" ]; then
        az login --tenant "$AZURE_TENANT_ID" --only-show-errors
    else
        az login --only-show-errors
    fi
    if [ ! -z "${AZURE_SUBSCRIPTION_ID+x}" ]; then
        az account set -s "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || azOk=false
    fi
    AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv 2> /dev/null) || true
    AZURE_TENANT_ID=$(az account show --query tenantId -o tsv 2> /dev/null) || true
}
##############################################################################
#- checkLoginAndSubscription
##############################################################################
checkLoginAndSubscription() {
    az account show -o none
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        printf "\nYou seems disconnected from Azure, running 'az login'."
        azLogin
    fi
    CURRENT_SUBSCRIPTION_ID=$(az account show --query 'id' --output tsv)
    if [ -z "$AZURE_SUBSCRIPTION_ID" ] || [ "$AZURE_SUBSCRIPTION_ID" != "$CURRENT_SUBSCRIPTION_ID" ]; then
        # query subscriptions
        printf  "\nYou have access to the following subscriptions:"
        az account list --query '[].{name:name,"subscription Id":id}' --output table

        printf "\nYour current subscription is:"
        az account show --query '[name,id]'
        # shellcheck disable=SC2154
        if [ -z "$CURRENT_SUBSCRIPTION_ID" ]; then
            echo  "
            You will need to use a subscription with permissions for creating service principals (owner role provides this).
            If you want to change to a different subscription, enter the name or id.
            Or just press enter to continue with the current subscription."
            read -r  ">> " SUBSCRIPTION_ID

            if ! test -z "$SUBSCRIPTION_ID"
            then
                az account set -s "$SUBSCRIPTION_ID"
                printf  "\nNow using:"
                az account show --query '[name,id]'
                CURRENT_SUBSCRIPTION_ID=$(az account show --query 'id' --output tsv)
            fi
        fi
    fi
}
##############################################################################
#- isStorageAccountNameAvailable
##############################################################################
isStorageAccountNameAvailable(){
    name=$1
    if [ "$(az storage account check-name --name "${name}" | jq -r '.nameAvailable'  2>/dev/null)" =  "false" ]
    then
        echo "false"
    else
        echo "true"
    fi
}
##############################################################################
#- isKeyVaultNameAvailable
##############################################################################
isKeyVaultNameAvailable(){
    subscriptionId=$1
    name=$2
    if [ "$(az rest --method post --uri "https://management.azure.com/subscriptions/${subscriptionId}/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2019-09-01" --headers "Content-Type=application/json" --body "{\"name\": \"${name}\",\"type\": \"Microsoft.KeyVault/vaults\"}" 2>/dev/null | jq -r ".nameAvailable"  2>/dev/null)"  =  "false" ]
    then
        echo "false"
    else
        echo "true"
    fi
}
##############################################################################
#- isResourceGroupNameAvailable
##############################################################################
isResourceGroupNameAvailable(){
    name=$1
    NAME=$(az group show -n "${name}" --query name -o tsv 2> /dev/null)
    if [ ! -z "${NAME}" ]; then
        FOUND="false"
    else
        FOUND="true"
    fi
    echo "$FOUND"
}
##############################################################################
# getAvailableSuffix
##############################################################################
getAvailableSuffix() {
    SUBSCRIPTION_ID=$1
    FOUND="true"
    while [ "$FOUND" = "true" ]; do
        SUFFIX=$(shuf -i 1000-9999 -n 1)

        RG=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "pub" "$SUFFIX")
        if [ "$(isResourceGroupNameAvailable "$RG")" = "false" ]; then
            FOUND="true"
            continue
        else
            FOUND="false"
        fi
        RG=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "pri" "$SUFFIX")
        if [ "$(isResourceGroupNameAvailable "$RG")" = "false" ]; then
            FOUND="true"
            continue
        else
            FOUND="false"
        fi
        ST=$(getStorageAccountName "$AZURE_ENVIRONMENT" "pri" "$SUFFIX")
        if [ "$(isStorageAccountNameAvailable "$ST")" = "false" ]; then
            FOUND="true"
            continue
        else
            FOUND="false"
        fi
        ST=$(getStorageAccountName "$AZURE_ENVIRONMENT" "pub" "$SUFFIX")
        if [ "$(isStorageAccountNameAvailable "$ST")" = "false" ]; then
            FOUND="true"
            continue
        else
            FOUND="false"
        fi
        KV=$(getKeyVaultName "$AZURE_ENVIRONMENT" "pri" "$SUFFIX")
        if [ "$(isKeyVaultNameAvailable "$SUBSCRIPTION_ID" "$KV")" = "false" ]; then
            FOUND="true"
            continue
        else
            FOUND="false"
        fi
        KV=$(getKeyVaultName "$AZURE_ENVIRONMENT" "pub" "$SUFFIX")
        if [ "$(isKeyVaultNameAvailable "$SUBSCRIPTION_ID" "$KV")" = "false" ]; then
            FOUND="true"
            continue
        else
            FOUND="false"
        fi
    done
    echo "$SUFFIX"
    exit
}
##############################################################################
#- checkAzureConfiguration
##############################################################################
checkAzureConfiguration() {
    az account show -o none
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        printf "\nYou seems disconnected from Azure, running 'az login'."
        azLogin
    fi
    CURRENT_SUBSCRIPTION_ID=$(az account show --query 'id' --output tsv)
    CURRENT_TENANT_ID=$(az account show --query 'tenantId' --output tsv)
    if [ -z "${AZURE_SUBSCRIPTION_ID+x}" ] || [ "$AZURE_SUBSCRIPTION_ID" != "$CURRENT_SUBSCRIPTION_ID" ]; then
        # query subscriptions
        # printf  "\nYou have access to the following subscriptions:"
        # az account list --query '[].{name:name,"subscription Id":id}' --output table

        # printf "\nYour current subscription is:"
        # az account show --query '[name,id]'
        # shellcheck disable=SC2154
        if [ -z "$CURRENT_SUBSCRIPTION_ID" ]; then
            echo  "
            You will need to use a subscription with permissions for creating service principals (owner role provides this).
            If you want to change to a different subscription, enter the name or id.
            Or just press enter to continue with the current subscription."
            read -r  ">> " SUBSCRIPTION_ID

            if ! test -z "$SUBSCRIPTION_ID"
            then
                az account set -s "$SUBSCRIPTION_ID"
                printf  "\nNow using:"
                az account show --query '[name,id]'
                CURRENT_SUBSCRIPTION_ID=$(az account show --query 'id' --output tsv)
                CURRENT_TENANT_ID=$(az account show --query 'tenantId' --output tsv)
            fi
        fi
    fi
    # if variable CONFIGURATION_FILE is set, read varaiable values in configuration file.
    if [ "$CONFIGURATION_FILE" ]; then
        if [ -f "$CONFIGURATION_FILE" ]; then
            CONFIG_SUBSCRIPTION_ID=$(readConfigurationFileValue "$CONFIGURATION_FILE" "AZURE_SUBSCRIPTION_ID")
            if [ ! -z "${CONFIG_SUBSCRIPTION_ID}" ] && [ "$CONFIG_SUBSCRIPTION_ID" != "$CURRENT_SUBSCRIPTION_ID" ]; then
                printProgress "Updating a Azure Configuration file: $CONFIGURATION_FILE value: AZURE_SUBSCRIPTION_ID=$CURRENT_SUBSCRIPTION_ID..."
                updateConfigurationFile "$CONFIGURATION_FILE" "AZURE_SUBSCRIPTION_ID" "$CURRENT_SUBSCRIPTION_ID"
            fi
            CONFIG_TENANT_ID=$(readConfigurationFileValue "$CONFIGURATION_FILE" "AZURE_TENANT_ID")
            if [ ! -z "${CONFIG_TENANT_ID}" ] && [ "$CONFIG_TENANT_ID" != "$CURRENT_TENANT_ID" ]; then
                printProgress "Updating a Azure Configuration file: $CONFIGURATION_FILE value: AZURE_TENANT_ID=$CURRENT_TENANT_ID..."
                updateConfigurationFile "$CONFIGURATION_FILE" "AZURE_TENANT_ID" "$CURRENT_TENANT_ID"
            fi
            CONFIG_SUFFIX=$(readConfigurationFileValue "$CONFIGURATION_FILE" "AZURE_SUFFIX")
            if [ -z "${CONFIG_SUFFIX}" ]; then
                printProgress "Updating a Azure Configuration file: $CONFIGURATION_FILE value: AZURE_SUFFIX=$AZURE_SUFFIX..."
                AZURE_SUFFIX="$(getAvailableSuffix ${CURRENT_SUBSCRIPTION_ID})"
                printProgress "Using AZURE_SUFFIX=$AZURE_SUFFIX"
                updateConfigurationFile "$CONFIGURATION_FILE" "AZURE_SUFFIX" "$AZURE_SUFFIX"
            fi
        else
            printProgress "Creating a new Azure Configuration file: $CONFIGURATION_FILE..."
            AZURE_SUFFIX="$(getAvailableSuffix ${CURRENT_SUBSCRIPTION_ID})"
            printProgress "Using AZURE_SUFFIX=$AZURE_SUFFIX"
            cat > "$CONFIGURATION_FILE" << EOF
AZURE_REGION="${AZURE_REGION}"
AZURE_SUFFIX="${AZURE_SUFFIX}"
AZURE_SUBSCRIPTION_ID=${CURRENT_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${CURRENT_TENANT_ID}
AZURE_ENVIRONMENT=${AZURE_ENVIRONMENT}
AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP=""
EOF
        fi
        readConfigurationFile "$CONFIGURATION_FILE"
    fi
}
##############################################################################
#- isdiginstalled
##############################################################################
isdiginstalled() {
    command -v dig >/dev/null && echo "true" || echo "false"
}
##############################################################################
#- installdig
##############################################################################
installdig() {
    printProgress "Installing dig tool for DNS resolution check..."
    cmd="sudo apt update"
    #printProgress "${cmd}"
    eval "${cmd}" 2>/dev/null || true    
    cmd="sudo apt install -y dnsutils"
    #printProgress "${cmd}"
    eval "${cmd}" 2>/dev/null || true
}
##############################################################################
#- isPrivateIP
##############################################################################
isPrivateIP() {
    hostname="$1"    

    dig +short "${hostname}" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)' && echo "true" || echo "false"
}

##############################################################################
#- getCurrentObjectId
##############################################################################
getCurrentObjectId() {
  UserObjectId=$(az ad signed-in-user show --query id --output tsv 2>/dev/null) || true
  ServicePrincipalId=
  if [ -z "$UserObjectId" ]; then
      # shellcheck disable=SC2154
      ServicePrincipalId=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null)
      ObjectId="${ServicePrincipalId}"
  else
      ObjectId="${UserObjectId}"
  fi
  echo "$ObjectId"
}
##############################################################################
#- getCurrentUserPrincipalName
##############################################################################
getCurrentUserPrincipalName() {
  UserPrincipalName=$(az ad signed-in-user show --query userPrincipalName --output tsv 2>/dev/null) || true
  if [ -z "$UserPrincipalName" ]; then
      # shellcheck disable=SC2154
      ServicePrincipalId=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null)
      ObjectId="${ServicePrincipalId}"
  else
      ObjectId="${UserPrincipalName}"
  fi
  echo "$ObjectId"
}
##############################################################################
#- getCurrentObjectType
##############################################################################
getCurrentObjectType() {
  UserObjectId=$(az ad signed-in-user show --query id --output tsv 2>/dev/null) || true
  ObjectType="User"
  if [ -z "$UserObjectId" ]; then
      # shellcheck disable=SC2154
      ServicePrincipalId=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null)
      ObjectType="ServicePrincipal"
  fi
  echo "$ObjectType"
}

##############################################################################
#- updateSecretInKeyVault: Update secret in Key Vault
#  arg 1: Key Vault Name
#  arg 2: secret name
#  arg 3: Value
#  arg 4: verbose (true/false)
##############################################################################
updateSecretInKeyVault(){
    kv="$1"
    secret="$2"
    value="$3"
    verbose="$4"
    if [ "$verbose" = "true" ]; then
        printProgress "Creating/Updating secret in Key Vault: ${kv} secret name: ${secret}"
    fi

    cmd="az keyvault secret set --vault-name \"${kv}\" --name \"${secret}\" --value \"${value}\" --output none"
    # printProgress "${cmd}"
    eval "${cmd}"
    checkError
    # printProgress "${secret}=${value}"
}
##############################################################################
#- readSecretInKeyVault: Read secret from Key Vault
#  arg 1: Key Vault Name
#  arg 2: secret name
##############################################################################
readSecretInKeyVault(){
    kv="$1"
    secret="$2"

    cmd="az keyvault secret show --vault-name \"${kv}\" --name \"${secret}\"  --query \"value\" -o tsv "
    #printProgress "${cmd}"
    eval "${cmd}" 2>/dev/null || true
    #checkError
}
##############################################################################
#- getLatestDeploymentNameInResourceGroup
##############################################################################
getLatestDeploymentNameInResourceGroup()
{
    RG="$1"
    PREFIX="$2"

    cmd="az deployment group list --resource-group \"${RG}\" --query \"sort_by([?starts_with(name, '${PREFIX}')], &properties.timestamp)[-1].name\" -o tsv"
    #printProgress "$cmd"
    RESULT=$(eval "$cmd")
    checkError

    echo "${RESULT}"
}
##############################################################################
#- openStorageFirewall
##############################################################################
openStorageFirewall()
{
    storage="$1"
    resourceGroup="$2"

    printProgress "Opening Storage Account Firewall ..."
    cmd="az storage account update -n ${storage} -g ${resourceGroup} --default-action Allow --public-network-access Enabled --output none"
    printProgress "$cmd"
    eval "$cmd"
    sleep 30
}
##############################################################################
#- closeStorageFirewall
##############################################################################
closeStorageFirewall()
{
    storage="$1"
    resourceGroup="$2"

    printProgress "Closing Storage Account Firewall ..."
    cmd="az storage account update -n ${storage} -g ${resourceGroup} --default-action Deny --public-network-access Disabled --output none"
    printProgress "$cmd"
    eval "$cmd"
    sleep 30
}
##############################################################################
#- uploadFile
##############################################################################
uploadFile ()
{
    storageAccount="$1"
    container="$2"
    fileSource="$3"
    fileDestination="$4"

    printProgress "Uploading file to Azure Storage ${storageAccount} ..."
    cmd="az storage blob upload \
      --auth-mode login \
      --account-name ${storageAccount} \
      --container-name ${container} \
      --file ${fileSource} --name ${fileDestination} --overwrite --output none"
    printProgress "$cmd"
    eval "$cmd"
}

##############################################################################
#- downloadFile
##############################################################################
downloadFile ()
{
    storageAccount="$1"
    container="$2"
    fileSource="$3"
    fileDestination="$4"

    printProgress "Downloading file from Azure Storage ${storageAccount} ..."
    cmd="az storage blob download \
      --auth-mode login \
      --account-name ${storageAccount} \
      --container-name ${container} \
      --name ${fileSource} --file ${fileDestination}  --output none"
    printProgress "$cmd"
    eval "$cmd"
}
##############################################################################
#- pushImage
##############################################################################
pushImage ()
{
    sourceImagePath="$1"
    containerLoginServer="$2"
    sourceImageName="${sourceImagePath##*/}"
    docker pull ${sourceImagePath}
    docker tag ${sourceImageName} ${containerLoginServer}/${sourceImageName}
    docker push ${containerLoginServer}/${sourceImageName}

}
##############################################################################
#- pullImage
##############################################################################
pullImage ()
{
    sourceImagePath="$1"
    containerLoginServer="$2"
    sourceImageName="${sourceImagePath##*/}"
    docker pull ${containerLoginServer}/${sourceImageName}
}
##############################################################################
#- getHostname
##############################################################################
getHostname() 
{
    url="$1"
    hostname=$(echo "$url" | awk -F/ '{print $3}')
    echo "$hostname"
}

DEFAULT_ACTION="action not set"
if [ -d "$SCRIPTS_DIRECTORY/../.config" ]; then
    DEFAULT_CONFIGURATION_FILE="$SCRIPTS_DIRECTORY/../.config/.default.env"
else
    DEFAULT_CONFIGURATION_FILE="$SCRIPTS_DIRECTORY/../.default.env"
fi
DEFAULT_ENVIRONMENT="dev"
DEFAULT_REGION="westus3"
DEFAULT_SUBSCRIPTION_ID=""
DEFAULT_TENANT_ID=""
DEFAULT_RESOURCE_GROUP="rg${DEFAULT_ENVIRONMENT}public"
DEFAULT_CONTAINER_IMAGE="hello-world:latest"
ARG_ACTION="${DEFAULT_ACTION}"
ARG_CONFIGURATION_FILE="${DEFAULT_CONFIGURATION_FILE}"
ARG_ENVIRONMENT="${DEFAULT_ENVIRONMENT}"
ARG_REGION="${DEFAULT_REGION}"
ARG_SUBSCRIPTION_ID="${DEFAULT_SUBSCRIPTION_ID}"
ARG_TENANT_ID="${DEFAULT_TENANT_ID}"
ARG_RESOURCE_GROUP="${DEFAULT_RESOURCE_GROUP}"
# shellcheck disable=SC2034
while getopts "a:c:e:r:s:t:g:" opt; do
    case $opt in
    a) ARG_ACTION=$OPTARG ;;
    c) ARG_CONFIGURATION_FILE=$OPTARG ;;
    e) ARG_ENVIRONMENT=$OPTARG ;;
    r) ARG_REGION=$OPTARG ;;
    s) ARG_SUBSCRIPTION_ID=$OPTARG ;;
    t) ARG_TENANT_ID=$OPTARG ;;
    g) ARG_RESOURCE_GROUP=$OPTARG ;;
    :)
        echo "Error: -${OPTARG} requires a value"
        exit 1
        ;;
    *)
        usage
        exit 1
        ;;
    esac
done

if [ $# -eq 0 ] || [ -z "${ARG_ACTION}" ] || [ -z "$ARG_CONFIGURATION_FILE" ]; then
    printError "Required parameters are missing"
    usage
    exit 1
fi
if [ "${ARG_ACTION}" != "deploy-public-vpn" ] && \
   [ "${ARG_ACTION}" != "azure-login" ] && \
   [ "${ARG_ACTION}" != "deploy-private-vpn" ] && \
   [ "${ARG_ACTION}" != "configure-private-vpn" ] && \
   [ "${ARG_ACTION}" != "remove-public-vpn" ] && \
   [ "${ARG_ACTION}" != "remove-private-vpn" ]; then
    printError "ACTION '${ARG_ACTION}' not supported, possible values: deploy-public-vpn, deploy-private-vpn, configure-private-vpn, remove-public-vpn, remove-private-vpn  "
    usage
    exit 1
fi
ACTION=${ARG_ACTION}
CONFIGURATION_FILE=""
if [ -n "${ARG_ENVIRONMENT}" ]; then
    AZURE_ENVIRONMENT="${ARG_ENVIRONMENT}"
fi
# if configuration file exists read subscription id and tenant id values in the file
if [ "$ARG_CONFIGURATION_FILE" ]; then
    if [ -f "$ARG_CONFIGURATION_FILE" ]; then
        readConfigurationFile "$ARG_CONFIGURATION_FILE"
    fi
    CONFIGURATION_FILE=${ARG_CONFIGURATION_FILE}
fi
if [ -n "${ARG_SUBSCRIPTION_ID}" ]; then
    AZURE_SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID}"
fi
if [ -n "${ARG_TENANT_ID}" ]; then
    AZURE_TENANT_ID="${ARG_TENANT_ID}"
fi
if [ -n "${ARG_REGION}" ]; then
    AZURE_REGION="${ARG_REGION}"
fi
if [ -n "${ARG_ENVIRONMENT}" ]; then
    AZURE_ENVIRONMENT="${ARG_ENVIRONMENT}"
fi

if [ "${ACTION}" = "azure-login" ] ; then
    printMessage "Azure Login..."
    azLogin
    checkLoginAndSubscription
    printMessage "Azure Login done"
    CURRENT_USER=$(az ad signed-in-user show --query userPrincipalName 2> /dev/null) || true
    CURRENT_SUBSCRIPTION_ID=$(az account show --query id --output tsv 2> /dev/null) || true
    CURRENT_TENANT_ID=$(az account show --query tenantId -o tsv 2> /dev/null) || true
    printMessage "You are logged in Azure CLI as user: $CURRENT_USER"
    printMessage "Your current subscription is: $CURRENT_SUBSCRIPTION_ID"
    printMessage "Your current tenant is: $CURRENT_TENANT_ID"
    if [ -f "$CONFIGURATION_FILE" ]; then
        printProgress "Updating configuration file: '${CONFIGURATION_FILE}'..."
        updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_REGION "${AZURE_REGION}"
        updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_SUBSCRIPTION_ID "${AZURE_SUBSCRIPTION_ID}"
        updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_TENANT_ID "${AZURE_TENANT_ID}"
        updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_ENVIRONMENT "${AZURE_ENVIRONMENT}"
    else
        printProgress "Creating a new Azure Configuration file: $CONFIGURATION_FILE..."
        AZURE_SUFFIX="$(getAvailableSuffix ${CURRENT_SUBSCRIPTION_ID})"
        printProgress "Using AZURE_SUFFIX=$AZURE_SUFFIX"
        cat > "$CONFIGURATION_FILE" << EOF
AZURE_REGION="${AZURE_REGION}"
AZURE_SUFFIX=${AZURE_SUFFIX}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_ENVIRONMENT=${AZURE_ENVIRONMENT}
AZURE_DEFAULT_AZURE_AI_RESOURCE_GROUP=""
EOF
    fi
    exit 0
fi
printProgress "Checking Azure Configuration..."
checkAzureConfiguration


if [ "${ACTION}" = "deploy-public-vpn" ] ; then
    cmd="az config set extension.use_dynamic_install=yes_without_prompt"
    printProgress "$cmd"
    eval "$cmd" 1>/dev/null 2>/dev/null || true

    VISIBILITY="pub"
    RESOURCE_GROUP_NAME=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "${VISIBILITY}" "${AZURE_SUFFIX}")
    if [ "$(az group exists --name "${RESOURCE_GROUP_NAME}")" = "false" ]; then
        printProgress "Create resource group  '${RESOURCE_GROUP_NAME}' in location '${AZURE_REGION}'"
        cmd="az group create -l ${AZURE_REGION} -n ${RESOURCE_GROUP_NAME}"
        printProgress "$cmd"
        eval "$cmd" 1>/dev/null
        checkError
    else
        printProgress "Resource group '${RESOURCE_GROUP_NAME}' already exists"
    fi
    DEFAULT_DEPLOYMENT_PREFIX="${AZURE_ENVIRONMENT}${VISIBILITY}${AZURE_SUFFIX}"

    setAzureResourceNames ${AZURE_ENVIRONMENT} "${VISIBILITY}" "${AZURE_SUFFIX}" "${RESOURCE_GROUP_NAME}"

    CLIENT_IP_ADDRESS=$(curl -s https://ifconfig.me)
    OBJECT_ID=$(getCurrentObjectId)
    if [ -z "${OBJECT_ID}" ] || [ "${OBJECT_ID}" = "null" ]; then
        printError "Cannot get current user Object Id"
        exit 1
    fi
    OBJECT_TYPE=$(getCurrentObjectType)
    printProgress "Deploy public Azure AI in resource group '${RESOURCE_GROUP_NAME}'"
    DEPLOY_NAME=$(date +"${DEFAULT_DEPLOYMENT_PREFIX}-%y%m%d%H%M%S")
    cmd="az deployment group create --resource-group $RESOURCE_GROUP_NAME  --name ${DEPLOY_NAME}   \
    --template-file $SCRIPTS_DIRECTORY/bicep/public-main.bicep \
    --parameters \
    location=${AZURE_REGION} \
    env=${AZURE_ENVIRONMENT} \
    visibility=${VISIBILITY} \
    suffix=${AZURE_SUFFIX} \
    objectId=\"${OBJECT_ID}\" objectType=\"${OBJECT_TYPE}\" clientIpAddress=\"${CLIENT_IP_ADDRESS}\"  \
     --verbose"
    printProgress "$cmd"
    eval "$cmd"
    checkError
    readDeploymentOutputs ${DEPLOY_NAME} ${RESOURCE_GROUP_NAME}

    printProgress "Testing access to Key Vault: ${AZURE_KEY_VAULT_NAME}"
    updateSecretInKeyVault ${AZURE_KEY_VAULT_NAME} "testsecret" "testsecretvalue" true
    value=$(readSecretInKeyVault ${AZURE_KEY_VAULT_NAME} "testsecret" true)
    printProgress "Read secret from Key Vault: ${value}"
    if [ "$value" != "testsecretvalue" ]; then
        printError "Failed to read/write secret in Key Vault, value read: ${value}"
    else
        printMessage "Successfully read/write secret in Key Vault"
    fi
    TEMPDIR=$(mktemp -d)
    printProgress "Uploading file to Azure Storage ${AZURE_STORAGE_ACCOUNT_NAME} ..."
    uploadFile "${AZURE_STORAGE_ACCOUNT_NAME}" "${AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME}"  "$SCRIPTS_DIRECTORY/data/testdata.csv" "data/testdata.csv"
    downloadFile "${AZURE_STORAGE_ACCOUNT_NAME}" "${AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME}" "data/testdata.csv" "${TEMPDIR}/testdata.csv" 

    if cmp -s "$SCRIPTS_DIRECTORY/data/testdata.csv" "${TEMPDIR}/testdata.csv" ; then
        printMessage "Files are identical, successfully read/write file in Azure Storage"
    else
        printError "Files differ, failed to read/write file in Azure Storage"
    fi

    printProgress "Pushing and Pulling container image to Azure Container Registry ${AZURE_ACR_NAME} ..."
    cmd="az acr login --name ${AZURE_ACR_NAME}"
    printProgress "$cmd"
    eval "$cmd"
    pushImage "${DEFAULT_CONTAINER_IMAGE}" "${AZURE_ACR_LOGIN_SERVER}"
    pullImage "${DEFAULT_CONTAINER_IMAGE}" "${AZURE_ACR_LOGIN_SERVER}"
    sourceImageName="${DEFAULT_CONTAINER_IMAGE##*/}"

    if [ "$(docker images -q ${AZURE_ACR_LOGIN_SERVER}/${sourceImageName} 2> /dev/null)" = "" ]; then
        printError "Failed to pull image from Azure Container Registry ${AZURE_ACR_NAME}"
    else
        printMessage "Successfully pushed and pulled container image in Azure Container Registry"
    fi

    printProgress "Key Vault API hostname: $(getHostname $AZURE_KEY_VAULT_URI)"
    printProgress "Container Regsitry hostname: $AZURE_ACR_LOGIN_SERVER"
    printProgress "Blob API hostname: $(getHostname $AZURE_STORAGE_BLOB_URI)"
    printProgress "File API hostname: $(getHostname $AZURE_STORAGE_FILE_URI)"
    printProgress "DFS API hostname: $(getHostname $AZURE_STORAGE_DFS_URI)"
    
    # Install dig tool if not exist for DNS resolution check
    if [ "$(isdiginstalled)" = "false" ]; then  
        installdig
    fi

    key_vault_hostname=$(getHostname $AZURE_KEY_VAULT_URI)
    if [ "$(isPrivateIP $key_vault_hostname)" = "false" ]; then
        printMessage "Key Vault Hostname ${key_vault_hostname} is a public IP"
    else
        printError "Key Vault Hostname ${key_vault_hostname} is not a public IP"
        exit 1
    fi

    acr_hostname=$AZURE_ACR_LOGIN_SERVER
    if [ "$(isPrivateIP $acr_hostname)" = "false" ]; then
        printMessage "Container Registry Hostname ${acr_hostname} is a public IP"
    else
        printError "Container Registry Hostname ${acr_hostname} is not a public IP"
        exit 1
    fi

    blob_api_hostname=$(getHostname $AZURE_STORAGE_BLOB_URI)
    if [ "$(isPrivateIP $blob_api_hostname)" = "false" ]; then
        printMessage "Blob API Hostname ${blob_api_hostname} is a public IP"
    else
        printError "Blob API Hostname ${blob_api_hostname} is not a public IP"
        exit 1
    fi

    file_api_hostname=$(getHostname $AZURE_STORAGE_FILE_URI)
    if [ "$(isPrivateIP $file_api_hostname)" = "false" ]; then
        printMessage "File API Hostname ${file_api_hostname} is a public IP"
    else
        printError "File API Hostname ${file_api_hostname} is not a public IP"
        exit 1
    fi

    dfs_api_hostname=$(getHostname $AZURE_STORAGE_DFS_URI)
    if [ "$(isPrivateIP $dfs_api_hostname)" = "false" ]; then
        printMessage "DFS API Hostname ${dfs_api_hostname} is a public IP"
    else
        printError "DFS API Hostname ${dfs_api_hostname} is not a public IP"
        exit 1
    fi

    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_STORAGE_ACCOUNT_NAME "${AZURE_STORAGE_ACCOUNT_NAME}"
    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_KEY_VAULT_NAME "${AZURE_KEY_VAULT_NAME}"
    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_ACR_NAME "${AZURE_ACR_NAME}"
    exit 0
fi


if [ "${ACTION}" = "deploy-private-vpn" ] ; then
    cmd="az config set extension.use_dynamic_install=yes_without_prompt"
    printProgress "$cmd"
    eval "$cmd" 1>/dev/null 2>/dev/null || true

    VISIBILITY="pri"
    RESOURCE_GROUP_NAME=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "${VISIBILITY}" "${AZURE_SUFFIX}")
    if [ "$(az group exists --name "${RESOURCE_GROUP_NAME}")" = "false" ]; then
        printProgress "Create resource group  '${RESOURCE_GROUP_NAME}' in location '${AZURE_REGION}'"
        cmd="az group create -l ${AZURE_REGION} -n ${RESOURCE_GROUP_NAME}"
        printProgress "$cmd"
        eval "$cmd" 1>/dev/null
        if [ -z "${AZURE_SUFFIX+x}" ] || [ "${AZURE_SUFFIX}" = "" ]; then
            SUFFIX=$(shuf -i 1000-9999 -n 1)
            updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_SUFFIX "${SUFFIX}"
            AZURE_SUFFIX="${SUFFIX}"
        fi
        checkError
    else
        printProgress "Resource group '${RESOURCE_GROUP_NAME}' already exists"
    fi
    DEFAULT_DEPLOYMENT_PREFIX="${AZURE_ENVIRONMENT}${VISIBILITY}${AZURE_SUFFIX}"

    setAzureResourceNames ${AZURE_ENVIRONMENT} "${VISIBILITY}" "${AZURE_SUFFIX}" "${RESOURCE_GROUP_NAME}"
    printProgress "Deploy private key Vault, Storage and registry in resource group '${RESOURCE_GROUP_NAME}'"
    
    CLIENT_IP_ADDRESS=$(curl -s https://ifconfig.me)
    OBJECT_ID=$(getCurrentObjectId)
    if [ -z "${OBJECT_ID}" ] || [ "${OBJECT_ID}" = "null" ]; then
        printError "Cannot get current user Object Id"
        exit 1
    fi    
    OBJECT_TYPE=$(getCurrentObjectType)
  
    DEPLOY_NAME=$(date +"${DEFAULT_DEPLOYMENT_PREFIX}-%y%m%d%H%M%S")
    cmd="az deployment group create --resource-group $RESOURCE_GROUP_NAME --name ${DEPLOY_NAME} \
    --template-file $SCRIPTS_DIRECTORY/bicep/private-main.bicep \
    --parameters \
    location=${AZURE_REGION} \
    env=${AZURE_ENVIRONMENT} \
    visibility=${VISIBILITY} \
    suffix=${AZURE_SUFFIX} \
    vnetAddressPrefix=\"10.13.0.0/16\" \
    privateEndpointSubnetAddressPrefix=\"10.13.0.0/24\" \
    bastionSubnetAddressPrefix=\"10.13.1.0/24\" \
    datagwSubnetAddressPrefix=\"10.13.2.0/24\" \
    gatewaySubnetAddressPrefix=\"10.13.3.0/24\" \
    dnsDelegationSubnetAddressPrefix=\"10.13.4.0/24\" \
    dnsDelegationSubnetIPAddress=\"10.13.4.22\" \
    dnsZoneResourceGroupName=\"${RESOURCE_GROUP_NAME}\" \
    dnsZoneSubscriptionId=\"${AZURE_SUBSCRIPTION_ID}\" \
    newOrExistingDnsZones=\"new\" \
    objectId=\"${OBJECT_ID}\"  objectType=\"${OBJECT_TYPE}\" clientIpAddress=\"${CLIENT_IP_ADDRESS}\" \
     --verbose"
    printProgress "$cmd"
    eval "$cmd"
    checkError
    readDeploymentOutputs ${DEPLOY_NAME} ${RESOURCE_GROUP_NAME}

    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_STORAGE_ACCOUNT_NAME "${AZURE_STORAGE_ACCOUNT_NAME}"
    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_KEY_VAULT_NAME "${AZURE_KEY_VAULT_NAME}"
    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_ACR_NAME "${AZURE_ACR_NAME}"
    exit 0
fi

if [ "${ACTION}" = "configure-private-vpn" ] ; then
    cmd="az config set extension.use_dynamic_install=yes_without_prompt"
    printProgress "$cmd"
    eval "$cmd" 1>/dev/null 2>/dev/null || true
    
    VISIBILITY="pri"
    RESOURCE_GROUP_NAME=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "${VISIBILITY}" "${AZURE_SUFFIX}")
    DEFAULT_DEPLOYMENT_PREFIX="${AZURE_ENVIRONMENT}${VISIBILITY}${AZURE_SUFFIX}"

    setAzureResourceNames ${AZURE_ENVIRONMENT} "${VISIBILITY}" "${AZURE_SUFFIX}" "${RESOURCE_GROUP_NAME}"
    readDeploymentOutputs ${DEPLOY_NAME} ${RESOURCE_GROUP_NAME}

    if [ "$(isdiginstalled)" = "false" ]; then
        printProgress "Installing 'dig' command line tool"
        installdig
    fi      
    if [ "$(isPrivateIP $(getHostname $AZURE_STORAGE_BLOB_URI))" = "false" ]; then
        printError "VPN connection required before configuring private Key vault, Storage and Registry, since the storage account is not behind private endpoint. Please connect to the VPN and run the script again to configure private Key vault, Storage and Registry."
        exit 1
    fi

    printProgress "Configure private Key vault, Storage and Registry in resource group '${RESOURCE_GROUP_NAME}'"    
    CLIENT_IP_ADDRESS=$(curl -s https://ifconfig.me)
    OBJECT_ID=$(getCurrentObjectId)
    if [ -z "${OBJECT_ID}" ] || [ "${OBJECT_ID}" = "null" ]; then
        printError "Cannot get current user Object Id"
        exit 1
    fi    
    OBJECT_TYPE=$(getCurrentObjectType)
    DEPLOY_NAME=$(getLatestDeploymentNameInResourceGroup ${RESOURCE_GROUP_NAME} "${DEFAULT_DEPLOYMENT_PREFIX}")
    printProgress "Read values associated with deployment '${DEPLOY_NAME}' in resource group '${RESOURCE_GROUP_NAME}'"
    readDeploymentOutputs ${DEPLOY_NAME} ${RESOURCE_GROUP_NAME}

    printProgress "Testing access to Key Vault: ${AZURE_KEY_VAULT_NAME}"
    updateSecretInKeyVault ${AZURE_KEY_VAULT_NAME} "testsecret" "testsecretvalue" true
    value=$(readSecretInKeyVault ${AZURE_KEY_VAULT_NAME} "testsecret" true)
    printProgress "Read secret from Key Vault: ${value}"
    if [ "$value" != "testsecretvalue" ]; then
        printError "Failed to read/write secret in Key Vault, value read: ${value}"
    else
        printMessage "Successfully read/write secret in Key Vault"
    fi
    TEMPDIR=$(mktemp -d)
    printProgress "Uploading file to Azure Storage ${AZURE_STORAGE_ACCOUNT_NAME} ..."
    uploadFile "${AZURE_STORAGE_ACCOUNT_NAME}" "${AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME}"  "$SCRIPTS_DIRECTORY/data/testdata.csv" "data/testdata.csv"
    downloadFile "${AZURE_STORAGE_ACCOUNT_NAME}" "${AZURE_STORAGE_ACCOUNT_DEFAULT_CONTAINER_NAME}" "data/testdata.csv" "${TEMPDIR}/testdata.csv" 

    if cmp -s "$SCRIPTS_DIRECTORY/data/testdata.csv" "${TEMPDIR}/testdata.csv" ; then
        printMessage "Files are identical, successfully read/write file in Azure Storage"
    else
        printError "Files differ, failed to read/write file in Azure Storage"
    fi

    printProgress "Pushing and Pulling container image to Azure Container Registry ${AZURE_ACR_NAME} ..."
    cmd="az acr login --name ${AZURE_ACR_NAME}"
    printProgress "$cmd"
    eval "$cmd"
    pushImage "${DEFAULT_CONTAINER_IMAGE}" "${AZURE_ACR_LOGIN_SERVER}"
    pullImage "${DEFAULT_CONTAINER_IMAGE}" "${AZURE_ACR_LOGIN_SERVER}"
    sourceImageName="${DEFAULT_CONTAINER_IMAGE##*/}"

    if [ "$(docker images -q ${AZURE_ACR_LOGIN_SERVER}/${sourceImageName} 2> /dev/null)" = "" ]; then
        printError "Failed to pull image from Azure Container Registry ${AZURE_ACR_NAME}"
    else
        printMessage "Successfully pushed and pulled container image in Azure Container Registry"
    fi

    printProgress "Key Vault API hostname: $(getHostname $AZURE_KEY_VAULT_URI)"
    printProgress "Container Regsitry hostname: $AZURE_ACR_LOGIN_SERVER"
    printProgress "Blob API hostname: $(getHostname $AZURE_STORAGE_BLOB_URI)"
    printProgress "File API hostname: $(getHostname $AZURE_STORAGE_FILE_URI)"
    printProgress "DFS API hostname: $(getHostname $AZURE_STORAGE_DFS_URI)"
    
    # Install dig tool if not exist for DNS resolution check
    if [ "$(isdiginstalled)" = "false" ]; then  
        installdig
    fi

    key_vault_hostname=$(getHostname $AZURE_KEY_VAULT_URI)
    if [ "$(isPrivateIP $key_vault_hostname)" = "true" ]; then
        printMessage "Key Vault Hostname ${key_vault_hostname} is a private IP"
    else
        printError "Key Vault Hostname ${key_vault_hostname} is not a private IP"
        exit 1
    fi

    acr_hostname=$AZURE_ACR_LOGIN_SERVER
    if [ "$(isPrivateIP $acr_hostname)" = "true" ]; then
        printMessage "Container Registry Hostname ${acr_hostname} is a private IP"
    else
        printError "Container Registry Hostname ${acr_hostname} is not a private IP"
        exit 1
    fi

    blob_api_hostname=$(getHostname $AZURE_STORAGE_BLOB_URI)
    if [ "$(isPrivateIP $blob_api_hostname)" = "true" ]; then
        printMessage "Blob API Hostname ${blob_api_hostname} is a private IP"
    else
        printError "Blob API Hostname ${blob_api_hostname} is not a private IP"
        exit 1
    fi

    file_api_hostname=$(getHostname $AZURE_STORAGE_FILE_URI)
    if [ "$(isPrivateIP $file_api_hostname)" = "true" ]; then
        printMessage "File API Hostname ${file_api_hostname} is a private IP"
    else
        printError "File API Hostname ${file_api_hostname} is not a private IP"
        exit 1
    fi

    dfs_api_hostname=$(getHostname $AZURE_STORAGE_DFS_URI)
    if [ "$(isPrivateIP $dfs_api_hostname)" = "true" ]; then
        printMessage "DFS API Hostname ${dfs_api_hostname} is a private IP"
    else
        printError "DFS API Hostname ${dfs_api_hostname} is not a private IP"
        exit 1
    fi

    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_STORAGE_ACCOUNT_NAME "${AZURE_STORAGE_ACCOUNT_NAME}"
    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_KEY_VAULT_NAME "${AZURE_KEY_VAULT_NAME}"
    updateConfigurationFile "${CONFIGURATION_FILE}" AZURE_ACR_NAME "${AZURE_ACR_NAME}"
    exit 0
fi


if [ "${ACTION}" = "remove-public-vpn" ] ; then
    VISIBILITY="pub"
    RESOURCE_GROUP_NAME=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "${VISIBILITY}" "${AZURE_SUFFIX}")
    if [ "$(az group exists --name "${RESOURCE_GROUP_NAME}")" = "true" ]; then
        printProgress "Remove resource group  '${RESOURCE_GROUP_NAME}' in location '${AZURE_REGION}'"
        cmd="az group delete  -n ${RESOURCE_GROUP_NAME} -y"
        printProgress "$cmd"
        eval "$cmd" 1>/dev/null
        checkError
    else
        printProgress "Resource group '${RESOURCE_GROUP_NAME}' doesn't exists"
    fi
    exit 0
fi

if [ "${ACTION}" = "remove-private-vpn" ] ; then
    VISIBILITY="pri"
    RESOURCE_GROUP_NAME=$(getVPNResourceGroupName "${AZURE_ENVIRONMENT}" "${VISIBILITY}" "${AZURE_SUFFIX}")
    if [ "$(az group exists --name "${RESOURCE_GROUP_NAME}")" = "true" ]; then
        printProgress "Remove resource group  '${RESOURCE_GROUP_NAME}' in location '${AZURE_REGION}'"
        cmd="az group delete  -n ${RESOURCE_GROUP_NAME} -y"
        printProgress "$cmd"
        eval "$cmd" 1>/dev/null
        checkError
    else
        printProgress "Resource group '${RESOURCE_GROUP_NAME}' doesn't exists"
    fi
    exit 0
fi

