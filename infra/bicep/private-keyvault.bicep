@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The base name to be appended to all provisioned resources.')
@maxLength(13)
param baseName string

@description('Name of the key vault resource.')
param keyVaultName string

@description('The name of the virtual network for virtual network integration.')
param vnetName string

@description('The name of the virtual network subnet to be used for private endpoints.')
param subnetName string

@description('The name of the resource group containing the virtual network.')
param vnetResourceGroupName  string

@description('The Private DNS Zone id for registering key vault private endpoint.')
param keyVaultPrivateDnsZoneId string

@description('The user object Id of the user or service principal running the script.')
param objectId string = ''

@description('The  object type User or ServicePrincipal.')
param objectType string = 'User'

@description('The tags to be applied to the provisioned resources.')
param tags object

var privateSubnetId = '${resourceId(vnetResourceGroupName,'Microsoft.Network/virtualNetworks', vnetName)}/subnets/${subnetName}'

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
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'disabled'
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

// Azure Key Vault "Private Endpoints" and "Private DNSZoneGroups" (A Record)
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-03-01' = {
  name: 'pe-kv-vault-${baseName}'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-kv-vault-${baseName}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }

  resource keyVaultPrivateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'keyVaultPrivateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: keyVaultPrivateDnsZoneId
          }
        }
      ]
    }
  }
}

output outKeyVaultName string = keyVault.name
output outKeyVaultId string = keyVault.id
output outKeyVaultUri string = keyVault.properties.vaultUri
