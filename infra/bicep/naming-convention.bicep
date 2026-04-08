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

output azureMLName string = 'azml${baseName}'
output azureMLComputeInstanceName string = 'ci${baseName}'
output azureMLComputeGPUSize string = 'Standard_NC4as_T4_v3'
output azureMLComputeCPUSize string = 'Standard_DS11_v2'
output foundryName string = 'foundry${baseName}'
output foundryProjectName string = 'foundryproject${baseName}'
output acrName string = 'acr${baseName}'
output appInsightsName string = 'appi${baseName}'
output vnetName string = 'vnet${baseName}'
output storageAccountName string = 'st${baseName}'
output storageAccountDefaultContainerName string = 'test${baseName}'
output keyVaultName string = 'kv${baseName}'
output privateEndpointSubnetName string = 'snet${baseName}pe'
output datagwSubnetName string = 'snet${baseName}dtgw'
output vpnGatewayName string = 'vnetvpngateway${baseName}'
output vpnGatewayPublicIpName string = 'vnetvpngatewaypip${baseName}'
output dnsResolverName string = 'vnetdnsresolver${baseName}'
output bastionSubnetName string = 'AzureBastionSubnet'
output bastionHostName string = 'bastion${baseName}'
output bastionPublicIpName string = 'bastionpip${baseName}'
output gatewaySubnetName string = 'GatewaySubnet'
output dnsDelegationSubNetName string = 'DNSDelegationSubnet'
output baseName string = baseName
output resourceGroupAzureAIName string = 'rgazureai${baseName}'
