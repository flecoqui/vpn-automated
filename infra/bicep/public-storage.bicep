@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The name of the storage account.')
param storageAccountName string

@description('The name of the storage account default container.')
param defaultContainerName string

@description('The user object Id of the user or service principal running the script.')
param objectId string = ''

@description('The  object type User or ServicePrincipal.')
param objectType string = 'User'

@description('The client IP address.')
param clientIpAddress string = ''

@description('The tags to be applied to the provisioned resources.')
param tags object

// https://docs.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor
var roleStorageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var roleStorageFilePrivilegedContributor='69566ab7-960f-475b-8e7c-b3118f30c6bd'
var roleStorageFileSMBShareContributor = '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'


resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }  
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    isHnsEnabled: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: clientIpAddress != '' ? [
        {
          value: clientIpAddress
          action: 'Allow'
        }
      ] : []
    }
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: tags
}

resource storageFileSystem 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: '${storageAccount.name}/default/${defaultContainerName}'
  properties: {
    publicAccess: 'None'
  }
}


resource storageBlobRoleAssignment2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, objectId, roleStorageBlobDataContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataContributor)
    principalId: objectId
    principalType: objectType
  }
}

resource storageFileSMBShareContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, objectId, roleStorageFileSMBShareContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageFileSMBShareContributor)
    principalId: objectId
    principalType: objectType
  }
}

resource storageFilePrivilegedContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, objectId, roleStorageFilePrivilegedContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageFilePrivilegedContributor)
    principalId: objectId
    principalType: objectType
  }
}

output outStorageAccountName string = storageAccount.name
output outStorageFilesysName string = storageFileSystem.name
output outStorageAccountId string = storageAccount.id
output outStorageBlobUri string = storageAccount.properties.primaryEndpoints.blob
output outStorageFileUri string = storageAccount.properties.primaryEndpoints.file
output outStorageDfsUri string = storageAccount.properties.primaryEndpoints.dfs
