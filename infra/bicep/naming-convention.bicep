@description('The Azure Environment (dev, staging, preprod, prod,...)')
@maxLength(13)
param environment string = uniqueString(resourceGroup().id)

@description('The cloud visibility (pub, pri)')
@maxLength(7)
param visibility string = 'pub'

@description('The Azure suffix')
@maxLength(4)
param suffix string = '0000'


var baseName = toLower('${environment}${visibility}${suffix}')

output acrName string = 'acr${baseName}'
output appInsightsName string = 'appi${baseName}'
output vnetName string = 'vnet${baseName}'
output storageAccountName string = 'st${baseName}'
output storageAccountDefaultContainerName string = 'test${baseName}'
output keyVaultName string = 'kv${baseName}'
output privateEndpointSubnetName string = 'snet${baseName}pe'
output vpnGatewayName string = 'vnetvpngateway${baseName}'
output vpnGatewayPublicIpName string = 'vnetvpngatewaypip${baseName}'
output dnsResolverName string = 'vnetdnsresolver${baseName}'
output bastionSubnetName string = 'AzureBastionSubnet'
output bastionHostName string = 'bastion${baseName}'
output bastionPublicIpName string = 'bastionpip${baseName}'
output gatewaySubnetName string = 'GatewaySubnet'
output dnsDelegationSubNetName string = 'DNSDelegationSubnet'
output baseName string = baseName
output resourceGroupName string = 'rgvpn${baseName}'
