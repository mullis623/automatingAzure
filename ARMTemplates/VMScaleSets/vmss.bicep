@description('Details of the VM Scale Set required by the ARM Template.')
param VMSSDetails object

@description('Password for the Virtual Machine.')
@secure()
param adminPassword string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Details of the Virtual Network required by the ARM Template. Not built in this template')
param VnetDetails object

@description('Details of the Load Balancer required by the ARM Template.')
param LBDetails object

var vmssSubnetID = resourceId(VnetDetails.RGName, 'Microsoft.Network/virtualNetworks/subnets', VnetDetails.Name, VMSSDetails.subnetName)
var lbSubnetID = resourceId(VnetDetails.RGName, 'Microsoft.Network/virtualNetworks/subnets', VnetDetails.Name, LBDetails.subnetName)

resource LBDetails_Name 'Microsoft.Network/loadBalancers@2020-07-01' = {
  name: LBDetails.Name
  location: resourceGroup().location
  tags: {
    displayName: 'Application Load Balancer'
  }
  sku: {
    name: LBDetails.Sku
  }
  properties: {
    frontendIPConfigurations: [
      {
        properties: {
          subnet: {
            id: lbSubnetID
          }
          privateIPAllocationMethod: 'Dynamic'
        }
        name: 'LBFrontend'
      }
    ]
    backendAddressPools: [
      {
        name: 'AppBackendPool1'
      }
    ]
    loadBalancingRules: [
      {
        properties: {
          frontendIPConfiguration: {
            id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/frontendIpConfigurations/LBFrontend')
          }
          backendAddressPool: {
            id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/backendAddressPools/AppBackendPool1')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 4
          probe: {
            id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/probes/HealthProbe')
          }
        }
        name: 'lbrule'
      }
      {
        properties: {
          frontendIPConfiguration: {
            id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/frontendIpConfigurations/LBFrontend')
          }
          backendAddressPool: {
            id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/backendAddressPools/AppBackendPool1')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          idleTimeoutInMinutes: 4
          probe: {
            id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/probes/HealthProbe')
          }
        }
        name: 'lbruleSSL'
      }
    ]
    probes: [
      {
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
        name: 'HealthProbe'
      }
    ]
  }
  dependsOn: []
}

resource VMSSDetails_Name 'Microsoft.Compute/virtualMachineScaleSets@2020-12-01' = {
  name: VMSSDetails.Name
  location: location
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: VMSSDetails.SkuName
    capacity: VMSSDetails.Capacity
  }
  properties: {
    upgradePolicy: {
      mode: VMSSDetails.UpgradeMode
    }
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          caching: 'ReadWrite'
          createOption: 'FromImage'
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: VMSSDetails.OSVersion
          version: 'latest'
        }
      }
      extensionProfile: {
        extensions: [
          {
            name: 'HealthExtension'
            properties: {
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthWindows'
              typeHandlerVersion: '1.0'
              autoUpgradeMinorVersion: false
              settings: {
                protocol: 'http'
                port: '80'
                requestPath: '/'
              }
            }
          }
        ]
      }
      osProfile: {
        computerNamePrefix: VMSSDetails.Name
        adminUsername: VMSSDetails.adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          provisionVMAgent: true
        }
        secrets: [
          {
            sourceVault: {
              id: resourceId(VMSSDetails.certKVRGName, 'Microsoft.KeyVault/vaults', VMSSDetails.certKVName)
            }
            vaultCertificates: [
              {
                certificateUrl: reference(resourceId(VMSSDetails.certKVRGName, 'Microsoft.KeyVault/vaults/secrets', VMSSDetails.certKVName, VMSSDetails.certName), '2018-02-14', 'Full').Properties.secretUriWithVersion
                certificateStore: 'My'
              }
            ]
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${VMSSDetails.Name}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: '${VMSSDetails.Name}-ipconfig'
                  properties: {
                    subnet: {
                      id: vmssSubnetID
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: concat(resourceId('Microsoft.Network/loadBalancers', LBDetails.Name), '/backendAddressPools/AppBackendPool1')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}
