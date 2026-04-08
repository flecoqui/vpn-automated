@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The name of the Application Insights resource.')
param appInsightsName string

@description('The tags to be applied to the provisioned resources.')
param tags object



resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
  tags: tags
}

output outAppInsightsName string = appInsights.name
output outAppInsightsId string = appInsights.id
