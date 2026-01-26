// ---------------------------------------------------------
// Enterprise Secure Landing Zone - Infrastructure as Code
// Author: Computer Engineering Student, RSU
// Description: Provisions a secure network foundation with centralized logging, 
//              traffic segmentation, and identity-based compute resources.
// ---------------------------------------------------------

// 1. Parameters
// ---------------------------------------------------------

@description('Project name prefix for resource naming consistency')
param projectName string = 'secure-landing-zone'

@description('Deployment environment (e.g., dev, prod)')
@allowed([
  'dev'
  'prod'
])
param environment string = 'dev'

@description('Azure Region for resource deployment. Defaults to Resource Group location.')
param location string = resourceGroup().location

@description('Administrator username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Administrator password for the Virtual Machine (Input at runtime for security)')
@secure() // Hides the password in logs and UI
param adminPassword string

@description('Size of the Virtual Machine. Change if the SKU is unavailable in your region.')
param vmSize string = 'Standard_D2s_v3' 

// 2. Variables (Naming Convention Strategy)
// ---------------------------------------------------------
var logAnalyticsName = 'log-${projectName}-${environment}'
var vnetName = 'vnet-${projectName}-${environment}'
var nsgName = 'nsg-${projectName}-${environment}'
var vmName = 'vm-${projectName}-${environment}'
var nicName = 'nic-${vmName}'
var identityName = 'id-${vmName}'

// 3. Resources
// ---------------------------------------------------------

// --- Phase 1: Visibility Layer (Log Analytics) ---
// Centralized logging workspace to collect telemetry and security logs.
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // Pay-as-you-go pricing model
    }
    retentionInDays: 30 // Retention policy (Cost-optimized for Dev)
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true // Enforce RBAC for log access
    }
  }
}

// --- Phase 2: Governance Layer (Network Security) ---
// Network Security Group (NSG) to act as a stateful firewall for subnets.
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*' // Note: In production, restrict this to VPN/Bastion IP only.
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Enable NSG Flow Logs/Diagnostics to Log Analytics for security auditing.
resource nsgDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${nsgName}'
  scope: nsg
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'NetworkSecurityGroupEvent'
        enabled: true
      }
      {
        category: 'NetworkSecurityGroupRuleCounter'
        enabled: true
      }
    ]
  }
}

// --- Phase 3: Network Layer (VNet) ---
// Virtual Network segmentation to isolate frontend and backend workloads.
resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-frontend'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id // Associate NSG for traffic control
          }
        }
      }
      {
        name: 'snet-backend'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// --- Phase 4: Identity & Compute Layer ---

// User Assigned Managed Identity for Zero Trust implementation.
// Allows VM to authenticate to Azure services without hardcoded credentials.
resource vmIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

// Network Interface (NIC) for the VM.
resource nic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[1].id // Deploying to Backend Subnet (No Public Access)
          }
        }
      }
    ]
  }
}

// Virtual Machine (Compute Resource)
resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${vmIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize // Parameterized for flexibility across regions
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword // Securely injected at runtime
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// 4. Outputs
// ---------------------------------------------------------
output logAnalyticsID string = logAnalytics.id
output vnetId string = vnet.id
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
