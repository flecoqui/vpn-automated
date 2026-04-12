@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('The base name to be appended to all provisioned resources.')
@maxLength(13)
param baseName string = uniqueString(resourceGroup().id)

@description('The name of the virtual network.')
param vnetName string

@description('The name of the virtual network subnet to be used for private endpoints.')
param privateEndpointSubnetName string

@description('The virtual network IP space to use for the new virutal network.')
param vnetAddressPrefix string

@description('The IP space to use for the subnet for private endpoints.')
param privateEndpointSubnetAddressPrefix string

@description('The IP space to use for the AzureBastionSubnet subnet.')
param bastionSubnetAddressPrefix string

@description('The IP address prefix for the virtual network subnet used for VPN Gateway.')
param gatewaySubnetAddressPrefix string

@description('The IP address prefix for the virtual network subnet used dns delegation.')
param dnsDelegationSubnetAddressPrefix string

@description('The IP address prefix for the virtual network subnet used dns delegation.')
param dnsDelegationSubnetIPAddress string

@description('The client IP address.')
param clientIpAddress string = ''

@description('The tags to be applied to the provisioned resources.')
param tags object

@description('Admin username for the gateway VM.')
param vmAdminUsername string = 'azureuser'

@description('SSH public key for the gateway VM admin user.')
@secure()
param vmAdminSshPublicKey string

var gatewaySubnetName ='OpenVPNSubnet'
var dnsDelegationSubNetName = 'DNSDelegationSubnet'
var bastionSubnetName = 'AzureBastionSubnet'
var vmGatewayName = 'vm-gateway-${baseName}'
var vmGatewayPublicIpName = 'vm-gateway-pip-${baseName}'
var vmGatewayNic0Name = 'nic0-${vmGatewayName}'
var vmGatewayNic1Name = 'nic1-${vmGatewayName}'
var sshKeyName = 'sshkey-${baseName}'

  
// Please note that though not required for the recipe, the "AzureBastionSubnet" subnet has been created to maintain idempotency of the deployment
// in case user decides to create a bastion host in the same VNet for testing purpose.
resource vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    dhcpOptions: { dnsServers: [dnsDelegationSubnetIPAddress] }
    subnets: [
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          networkSecurityGroup: {
            id: defaultSubnetNsg.id
          }
        }
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetAddressPrefix
        }
      }
      {
        name: dnsDelegationSubNetName
        properties: {
          addressPrefix: dnsDelegationSubnetAddressPrefix
          networkSecurityGroup: {
            id: dnsDelegationSubnetNsg.id
          }
        }
      }
      {
        name: gatewaySubnetName
        properties: {
          addressPrefix: gatewaySubnetAddressPrefix
          networkSecurityGroup: {
            id: gatewaySubnetNsg.id
          }          
        }
      }
    ]
  }
}
// network security group for site
resource defaultSubnetNsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: '${vnetName}-default-nsg'
  location: location
  properties: {
    securityRules: []
  }
}

resource gatewaySubnetNsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: '${vnetName}-gateway-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          description: 'Locks inbound down to ssh default port 22.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: clientIpAddress
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}


resource dnsDelegationSubnetNsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: '${vnetName}-dns-delegation-nsg'
  location: location
  properties: {
    securityRules: []
  }
}

// ----------------------------------------------------
// LOCAL Private DNS Zone
// ----------------------------------------------------

resource privateDnsZoneLocal 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${baseName}.local'
  location: 'global'
}

// Link to VNET. Name should be the same as VNET as we can't have multiple links to the same VNET
resource vnetLinkLocal 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneLocal
  name: '${vnetName}-virtuallink'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: true
  }
}

// ------------------------------------------------------------------
// VPN Gateway
// ------------------------------------------------------------------

// Public IP for VPN Gateway
resource vpnGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: vmGatewayPublicIpName
  location: location
  zones: ['1']
  properties: { publicIPAllocationMethod: 'Static' }
  sku: { name: 'Standard' }
}

// NIC 0 — datagwSubnet, with public IP (VPN Gateway)
resource vmGatewayNic0 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: vmGatewayNic0Name
  location: location
  tags: tags
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${gatewaySubnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: vpnGatewayPublicIp.id
          }
        }
      }
    ]
  }
}

// NIC 1 — dnsDelegationSubnet, with static private IP (DNS resolver)
resource vmGatewayNic1 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: vmGatewayNic1Name
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${dnsDelegationSubNetName}'
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsDelegationSubnetIPAddress
        }
      }
    ]
  }
}

// Ubuntu VM hosting VPN Gateway and DNS resolver
resource vmGateway 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmGatewayName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
    }
    osProfile: {
      computerName: vmGatewayName
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: sshKey.properties.publicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmGatewayNic0.id
          properties: { primary: true }
        }
        {
          id: vmGatewayNic1.id
          properties: { primary: false }
        }
      ]
    }
  }
}


// VM extension to run install.sh
resource vmGatewayCustomScript 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vmGateway
  name: 'CustomScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: loadFileAsBase64('../scripts/install.sh')
    }
  }
}

resource sshKey 'Microsoft.Compute/sshPublicKeys@2023-03-01' = {
  name: sshKeyName
  location: resourceGroup().location
  properties: {
    publicKey:  vmAdminSshPublicKey
  }
}

output outVnetName string = vnet.name
output outVnetId string = vnet.id
output outPrivateEndpointSubnetName string = privateEndpointSubnetName
output outVpnGatewayPublicIp string = vpnGatewayPublicIp.properties.ipAddress
output outVpnGatewayPrivateIp string = vmGatewayNic0.properties.ipConfigurations[0].properties.privateIPAddress
output outDnsResolverPrivateIp string = vmGatewayNic1.properties.ipConfigurations[0].properties.privateIPAddress

