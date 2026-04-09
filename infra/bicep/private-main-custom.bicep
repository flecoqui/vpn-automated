@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The Azure Environment (dev, staging, preprod, prod,...)')
@maxLength(7)
param env string = 'dev'

@description('The cloud visibility (pub, pri)')
@maxLength(7)
param visibility string = 'pri'

@description('The Azure suffix')
@maxLength(4)
param suffix string = '0000'

@description('Admin username for the gateway VM.')
param vmAdminUsername string = 'azureuser'

@description('SSH public key for the gateway VM admin user.')
@secure()
param vmAdminSshPublicKey string

@description('The IP address prefix for the virtual network')
param vnetAddressPrefix string = '10.13.0.0/16'

@description('The IP address prefix for the virtual network subnet used for private endpoints.')
param privateEndpointSubnetAddressPrefix string = '10.13.0.0/24'

@description('The IP address prefix for the virtual network subnet used for AzureBastionSubnet subnet.')
param bastionSubnetAddressPrefix string =  '10.13.1.0/24'

@description('The IP address prefix for the virtual network subnet used for Azure AI Jump Box subnet.')
param datagwSubnetAddressPrefix string =  '10.13.2.0/24'

@description('The IP address prefix for the virtual network subnet used for VPN Gateway.')
param gatewaySubnetAddressPrefix string = '10.13.3.0/24'

@description('The IP address prefix for the virtual network subnet used dns delegation.')
param dnsDelegationSubnetAddressPrefix string = '10.13.4.0/24'

@description('The IP address prefix for the virtual network subnet used dns delegation.')
param dnsDelegationSubnetIPAddress string = '10.13.4.22'

@description('The name of the Azure resource group containing the Azure Private DNS Zones used for registering private endpoints.')
param dnsZoneResourceGroupName string = resourceGroup().name

@description('The ID of the Azure subscription containing the Azure Private DNS Zones used for registering private endpoints.')
param dnsZoneSubscriptionId string = subscription().subscriptionId

@description('Indicator if new Azure Private DNS Zones should be created, or using existing Azure Private DNS Zones.')
@allowed([
  'new'
  'existing'
])
param newOrExistingDnsZones string = 'new'

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
var baseName = namingModule.outputs.baseName
var tags = {
  baseName : baseName
}



// Networking related variables
var vnetName = namingModule.outputs.vnetName
var privateEndpointSubnetName = namingModule.outputs.privateEndpointSubnetName
var datagwSubnetName = namingModule.outputs.datagwSubnetName

// Private DNS Zone variables
var privateDnsNames = [
  'privatelink.vaultcore.azure.net'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.file.${environment().suffixes.storage}'
  'privatelink.dfs.${environment().suffixes.storage}'
  'privatelink.azurecr.io'
]

// Defining Private DNS Zones resource group and subscription id
var calcDnsZoneResourceGroupName = (newOrExistingDnsZones == 'new') ? resourceGroup().name : dnsZoneResourceGroupName
var calcDnsZoneSubscriptionId = (newOrExistingDnsZones == 'new') ? subscription().subscriptionId : dnsZoneSubscriptionId

// Getting the Ids for existing or newly created Private DNS Zones
var blobPrivateDnsZoneId = resourceId(calcDnsZoneSubscriptionId, calcDnsZoneResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.blob.${environment().suffixes.storage}')
var filePrivateDnsZoneId = resourceId(calcDnsZoneSubscriptionId, calcDnsZoneResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.file.${environment().suffixes.storage}')
var dfsPrivateDnsZoneId = resourceId(calcDnsZoneSubscriptionId, calcDnsZoneResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.dfs.${environment().suffixes.storage}') 
var acrPrivateDnsZoneId = resourceId(calcDnsZoneSubscriptionId, calcDnsZoneResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.azurecr.io')
var keyVaultPrivateDnsZoneId = resourceId(calcDnsZoneSubscriptionId, calcDnsZoneResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.vaultcore.azure.net')

module dnsZoneModule './private-dns-zones.bicep' = if (newOrExistingDnsZones == 'new') {
  name: 'dnsZoneDeploy'
  scope: resourceGroup()
  params: {
    privateDnsNames: privateDnsNames
    tags: tags
  }
}

module networkModule 'private-network-custom.bicep' = {
  name: 'networkDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    vnetName: vnetName
    privateEndpointSubnetName: privateEndpointSubnetName
    datagwSubnetName: datagwSubnetName
    vnetAddressPrefix: vnetAddressPrefix
    vmAdminUsername: vmAdminUsername
    vmAdminSshPublicKey: vmAdminSshPublicKey
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetAddressPrefix
    bastionSubnetAddressPrefix: bastionSubnetAddressPrefix
    datagwSubnetAddressPrefix: datagwSubnetAddressPrefix
    gatewaySubnetAddressPrefix: gatewaySubnetAddressPrefix
    dnsDelegationSubnetIPAddress: dnsDelegationSubnetIPAddress
    dnsDelegationSubnetAddressPrefix: dnsDelegationSubnetAddressPrefix
    tags: tags
  }
}

module privateDnsZoneVnetLinkModule './dns-zone-vnet-mapping.bicep' = [ for (names, i) in privateDnsNames: {
  name: 'privateDnsZoneVnetLinkDeploy-${i}'
  scope: resourceGroup(calcDnsZoneSubscriptionId, calcDnsZoneResourceGroupName)
  params: {
    privateDnsZoneName: names
    vnetId: networkModule.outputs.outVnetId
    vnetLinkName: '${networkModule.outputs.outVnetName}-link'
  }
  dependsOn: [
    dnsZoneModule
  ]
}]

module keyVaultModule 'private-keyvault.bicep' = {
  name: 'keyVaultDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    keyVaultName: namingModule.outputs.keyVaultName
    keyVaultPrivateDnsZoneId: keyVaultPrivateDnsZoneId
    vnetName: networkModule.outputs.outVnetName
    subnetName: networkModule.outputs.outPrivateEndpointSubnetName
    vnetResourceGroupName: calcDnsZoneResourceGroupName
    objectId: objectId 
    objectType: objectType
    tags: tags
  }
  dependsOn: [
    privateDnsZoneVnetLinkModule
  ]
}

module storageModule 'private-storage.bicep' = {
  name: 'StorageDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: namingModule.outputs.baseName
    storageAccountName: namingModule.outputs.storageAccountName
    defaultContainerName: namingModule.outputs.storageAccountDefaultContainerName
    vnetName: vnetName
    subnetName: privateEndpointSubnetName
    vnetResourceGroupName: calcDnsZoneResourceGroupName
    blobPrivateDnsZoneId: blobPrivateDnsZoneId
    filePrivateDnsZoneId: filePrivateDnsZoneId
    dfsPrivateDnsZoneId: dfsPrivateDnsZoneId
    objectId: objectId
    objectType: objectType
    clientIpAddress: clientIpAddress
    tags: tags
  }
}

module containerRegistryModule 'private-acr.bicep' = {
  name: 'acrDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    acrName: namingModule.outputs.acrName
    vnetName: networkModule.outputs.outVnetName
    objectId: objectId
    objectType: objectType    
    subnetName: networkModule.outputs.outPrivateEndpointSubnetName
    vnetResourceGroupName: calcDnsZoneResourceGroupName
    acrPrivateDnsZoneId: acrPrivateDnsZoneId
    tags: tags
  }
  dependsOn: [
    privateDnsZoneVnetLinkModule
  ]
}


module appInsightsModule 'private-appinsights.bicep' = {
  name: 'appInsightsDeploy'
  scope: resourceGroup()
  params: {
    location: location
    appInsightsName: namingModule.outputs.appInsightsName
    tags: tags
  }
}


output outVirtualNetworkName string = networkModule.outputs.outVnetName
output outPrivateEndpointSubnetName string = networkModule.outputs.outPrivateEndpointSubnetName
output outDataGWSubnetName string = networkModule.outputs.outDataGWSubnetName
output vpnGatewayPublicIp string = networkModule.outputs.outVpnGatewayPublicIp
output keyVaultName string = keyVaultModule.outputs.outKeyVaultName
output acrName string = containerRegistryModule.outputs.outAcrName 
output appInsightsName string = appInsightsModule.outputs.outAppInsightsName
output storageAccountName string = storageModule.outputs.outStorageAccountName

output keyVaultUri string = keyVaultModule.outputs.outKeyVaultUri
output acrLoginServer string = containerRegistryModule.outputs.outAcrLoginServer
output storageBlobUri string = storageModule.outputs.outStorageBlobUri
output storageFileUri string = storageModule.outputs.outStorageFileUri
output storageDfsUri string = storageModule.outputs.outStorageDfsUri
