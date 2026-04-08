@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('Name of the key vault resource.')
param keyVaultName string

@description('The user object Id of the user or service principal running the script.')
param objectId string = ''

@description('The  object type User or ServicePrincipal.')
param objectType string = 'User'

@description('The client IP address.')
param clientIpAddress string = ''

@description('The tags to be applied to the provisioned resources.')
param tags object


resource keyVault 'Microsoft.KeyVault/vaults@2021-10-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: [{
          value: clientIpAddress
        }]
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'enabled'
  }
}

var roleKeyVaultSecretOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
resource keyVaultSecretRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, objectId, roleKeyVaultSecretOfficer)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKeyVaultSecretOfficer)
    principalId: objectId
    principalType: objectType
  }
}
var roleKeyVaultCertificateOfficer = 'a4417e6f-fecd-4de8-b567-7b0420556985'
resource keyVaultCertificateRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, objectId, roleKeyVaultCertificateOfficer)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKeyVaultCertificateOfficer)
    principalId: objectId
    principalType: objectType
  }
}

output outKeyVaultName string = keyVault.name
output outKeyVaultId string = keyVault.id
output outKeyVaultUri string = keyVault.properties.vaultUri
