@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The name of the Azure Container Registry.')
param acrName string

@description('The user object Id of the user or service principal running the script.')
param objectId string = ''

@description('The  object type User or ServicePrincipal.')
param objectType string = 'User'

@description('The tags to be applied to the provisioned resources.')
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
  tags: tags
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

