@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The base name to be appended to all provisioned resources.')
@maxLength(13)
param baseName string

@description('The name of the storage account.')
param storageAccountName string

@description('The name of the storage account default container.')
param defaultContainerName string

@description('The name of the virtual network for virtual network integration.')
param vnetName string

@description('The name of the virtual network subnet to be used for private endpoints.')
param subnetName string

@description('The name of the resource group containing the virtual network.')
param vnetResourceGroupName  string

@description('The Private DNS Zone id for registering storage "blob" private endpoints.')
param blobPrivateDnsZoneId string

@description('The Private DNS Zone id for registering storage "file" private endpoints.')
param filePrivateDnsZoneId string

@description('The Private DNS Zone id for registering storage "dfs" private endpoints.')
param dfsPrivateDnsZoneId string

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
var roleStorageBlobDataReader='2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var roleStorageFilePrivilegedContributor='69566ab7-960f-475b-8e7c-b3118f30c6bd'
var roleStorageFileReader='b8eda974-7b85-4f76-af95-65846b26df6d'
var roleStorageFileSMBShareContributor = '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'

var privateSubnetId = '${resourceId(vnetResourceGroupName,'Microsoft.Network/virtualNetworks', vnetName)}/subnets/${subnetName}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    isHnsEnabled: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        {
          value: clientIpAddress
          action: 'Allow'
        }
      ]
    }
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
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

// Azure Storage Account "Private Endpoints" and "Private DNSZoneGroups" (A Record)
resource privateEndpointBlob 'Microsoft.Network/privateEndpoints@2021-03-01' = {
  name: 'pe-st-blob-${baseName}'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-st-blob-${baseName}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource dnsZonesGroupsBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-03-01' = {
  parent: privateEndpointBlob
  name: 'blobPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: blobPrivateDnsZoneId
        }
      }
    ]
  }
}

resource privateEndpointFile 'Microsoft.Network/privateEndpoints@2021-03-01' = {
  name: 'pe-st-file-${baseName}'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-st-file-${baseName}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

resource dnsZonesGroupsFile 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-03-01' = {
  parent: privateEndpointFile
  name: 'filePrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: filePrivateDnsZoneId
        }
      }
    ]
  }
}

resource privateEndpointDfs 'Microsoft.Network/privateEndpoints@2021-03-01' = {
  name: 'pe-st-dfs-${baseName}'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-st-dfs-${baseName}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

resource dnsZonesGroupsDfs 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-03-01' = {
  parent: privateEndpointDfs
  name: 'dfsPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: dfsPrivateDnsZoneId
        }
      }
    ]
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
output outStorageAccountId string = storageAccount.id
output outStorageFilesysName string = storageFileSystem.name
output outStorageBlobUri string = storageAccount.properties.primaryEndpoints.blob
output outStorageFileUri string = storageAccount.properties.primaryEndpoints.file
output outStorageDfsUri string = storageAccount.properties.primaryEndpoints.dfs
