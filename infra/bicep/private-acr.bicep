@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The base name to be appended to all provisioned resources.')
@maxLength(13)
param baseName string

@description('The name of the Azure Container Registry.')
param acrName string

@description('The user object Id of the user or service principal running the script.')
param objectId string = ''

@description('The  object type User or ServicePrincipal.')
param objectType string = 'User'

@description('The name of the virtual network for virtual network integration.')
param vnetName string

@description('The name of the virtual network subnet to be used for private endpoints.')
param subnetName string

@description('The name of the resource group containing the virtual network.')
param vnetResourceGroupName string

@description('The Private DNS Zone id for registering ACR private endpoint.')
param acrPrivateDnsZoneId string

@description('The tags to be applied to the provisioned resources.')
param tags object

var privateSubnetId = '${resourceId(vnetResourceGroupName,'Microsoft.Network/virtualNetworks', vnetName)}/subnets/${subnetName}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
  }
  tags: tags
}

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-03-01' = {
  name: 'pe-acr-${baseName}'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-acr-${baseName}'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }

  resource acrPrivateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'acrPrivateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: acrPrivateDnsZoneId
          }
        }
      ]
    }
  }
}

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var acrPushRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(objectId)) {
  name: guid(acr.id, objectId, acrPullRoleDefinitionId)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: objectId
    principalType: objectType
  }
}

resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(objectId)) {
  name: guid(acr.id, objectId, acrPushRoleDefinitionId)
  scope: acr
  properties: {
    roleDefinitionId: acrPushRoleDefinitionId
    principalId: objectId
    principalType: objectType
  }
}

output outAcrName string = acr.name
output outAcrLoginServer string = acr.properties.loginServer
output outAcrId string = acr.id

