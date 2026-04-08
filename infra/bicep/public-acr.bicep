@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The name of the Azure Container Registry.')
param acrName string

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

output outAcrName string = acr.name
output outAcrLoginServer string = acr.properties.loginServer
output outAcrId string = acr.id

