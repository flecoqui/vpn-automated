@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The Azure Environment (dev, staging, preprod, prod,...)')
@maxLength(7)
param env string = 'dev'

@description('The cloud visibility (pub, pri)')
@maxLength(7)
param visibility string = 'pub'

@description('The Azure suffix')
@maxLength(4)
param suffix string = '0000'

@description('The user object Id of the user or service principal running the script.')
param objectId string = ''

@description('The  object type User or ServicePrincipal.')
param objectType string = 'User'

@description('The client IP address.')
param clientIpAddress string = ''


module namingModule 'naming-convention.bicep' = {
  name: 'namingModule'
  params: {
    environment: env
    visibility: visibility
    suffix: suffix
  }
}

var tags = {
  baseName : namingModule.outputs.baseName
  environment: env
  visibility: visibility
  suffix: suffix
}

module keyVaultModule 'public-keyvault.bicep' = {
  name: 'keyVaultDeploy'
  scope: resourceGroup()
  params: {
    location: location
    keyVaultName: namingModule.outputs.keyVaultName
    clientIpAddress: clientIpAddress
    objectId: objectId
    objectType: objectType
    tags: tags
  }
}

module storageModule 'public-storage.bicep' = {
  name: 'storageDeploy'
  scope: resourceGroup()
  params: {
    location: location
    storageAccountName: namingModule.outputs.storageAccountName
    defaultContainerName: namingModule.outputs.storageAccountDefaultContainerName
    clientIpAddress: clientIpAddress
    foundryPrincipalId: foundryModule.outputs.foundryPrincipalId
    objectId: objectId
    objectType: objectType
    tags: tags
  }
}

module containerRegistryModule 'public-acr.bicep' = {
  name: 'acrDeploy'
  scope: resourceGroup()
  params: {
    location: location
    acrName: namingModule.outputs.acrName
    tags: tags
  }
}


module appInsightsModule 'public-appInsights.bicep' = {
  name: 'appInsightsDeploy'
  scope: resourceGroup()
  params: {
    location: location
    appInsightsName: namingModule.outputs.appInsightsName
    tags: tags
  }
}

output keyVaultName string = keyVaultModule.outputs.outKeyVaultName
output acrName string = containerRegistryModule.outputs.outAcrName 
output appInsightsName string = appInsightsModule.outputs.outAppInsightsName
output storageAccountName string = storageModule.outputs.outStorageAccountName
