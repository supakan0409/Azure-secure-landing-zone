// ---------------------------------------------------------
// Phase 1: The Foundation - Visibility Layer
// ---------------------------------------------------------
// 1. Parameters (ตัวแปรรับค่าจากภายนอก เพื่อให้ Code ยืดหยุ่น)
@description('ชื่อของโปรเจค ใช้เป็น prefix ในการตั้งชื่อ resource')
param projectName string = 'secure-landing-zone'

@description('สภาพแวดล้อม (Environment) เช่น dev, prod')
param environment string = 'dev'

@description('Location ที่จะสร้าง Resource (Default เป็น Southeast Asia คือสิงคโปร์ ใกล้ไทยสุด)')
param location string = resourceGroup().location

// สร้าง Variable สำหรับตั้งชื่อให้เป็นมาตรฐาน (Naming Convention)
var logAnalyticsName = 'log-${projectName}-${environment}'

// ---------------------------------------------------------
// 2. Resources (ตัว Resource จริงๆ ที่จะสร้างบน Azure)
// ---------------------------------------------------------

// สร้าง Log Analytics Workspace (ถังเก็บ Log กลาง)
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // รูปแบบการคิดเงินแบบ Pay-as-you-go (ใช้เท่าไหร่จ่ายเท่านั้น)
    }
    retentionInDays: 30 // เก็บ Log ไว้ 30 วัน (สำหรับ dev พอก่อน ถ้า prod อาจจะ 90+)
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true // Security: บังคับใช้ Permission ของ Azure RBAC เท่านั้น
    }
  }
}

// ---------------------------------------------------------
// 3. Outputs (ส่งค่ากลับมาเมื่อทำงานเสร็จ)
// ---------------------------------------------------------
output logAnalyticsID string = logAnalytics.id
output logAnalyticsName string = logAnalytics.name

// สร้าง Variable สำหรับชื่อ VNet
var vnetName = 'vnet-${projectName}-${environment}'
var nsgName = 'nsg-${projectName}-${environment}'

// ---------------------------------------------------------
// Security Layer (Governance) <-- ส่วนที่เพิ่มใหม่
// ---------------------------------------------------------

// สร้าง Network Security Group (Firewall ประจำ Subnet)
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH' // อนุญาตให้ Remote เข้าไปจัดการ Server
        properties: {
          priority: 1000 // เลขน้อย = ทำงานก่อน
          access: 'Allow'
          direction: 'Inbound' // ขาเข้า
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22' // Port มาตรฐานของ SSH
          sourceAddressPrefix: '*' // ⚠️ คำเตือน: ใน Lab เราเปิดหมดเพื่อความง่าย แต่ใน Prod ห้ามทำ!
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// เชื่อมต่อ NSG เข้ากับ Log Analytics (Diagnostic Settings)
resource nsgDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${nsgName}'
  scope: nsg
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'NetworkSecurityGroupEvent' // เก็บ Log การบล็อค/อนุญาต
        enabled: true
      }
      {
        category: 'NetworkSecurityGroupRuleCounter' // เก็บสถิติว่า Rule ไหนทำงานบ่อยสุด
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------
// Network Layer <-- แก้ไขส่วนนี้เพื่อผูก NSG
// ---------------------------------------------------------

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
          networkSecurityGroup: { // <-- ผูก NSG ที่นี่
            id: nsg.id 
          }
        }
      }
      {
        name: 'snet-backend'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { // <-- ผูก NSG ที่นี่เหมือนกัน (ใช้กฎเดียวกันไปก่อน)
            id: nsg.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output nsgId string = nsg.id

// สร้าง Variable สำหรับชื่อ Resource ใหม่
var vmName = 'vm-${projectName}-${environment}'
var nicName = 'nic-${vmName}'
var identityName = 'id-${vmName}'

// ---------------------------------------------------------
// Identity Layer (หัวใจของ Zero Trust)
// ---------------------------------------------------------

// สร้าง "บัตรประจำตัว" ให้ VM (User Assigned Managed Identity)
resource vmIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

// ---------------------------------------------------------
// Compute Layer (VM & Networking)
// ---------------------------------------------------------

// สร้าง Network Interface Card (NIC) - การ์ดแลน
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
            id: vnet.properties.subnets[1].id // ⚠️ ใส่ใน Backend Subnet (index 1) เพื่อความปลอดภัย
            // หมายเหตุ: ใส่ Backend แปลว่าจะไม่มี Public IP เข้าตรงๆ ไม่ได้ ต้องเข้าผ่าน Frontend หรือ VPN
            // แต่สำหรับ Lab นี้ ถ้าอยากเข้า SSH ง่ายๆ ให้เปลี่ยนเป็น index 0 (Frontend) และเพิ่ม Public IP (แต่มันจะยาว ผมขอข้าม Public IP เพื่อความง่ายก่อน)
          }
        }
      }
    ]
  }
}

// สร้าง Virtual Machine (Ubuntu Linux)
resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  identity: {
    type: 'UserAssigned' // บอกว่า VM นี้ถือบัตรที่เราสร้างไว้
    userAssignedIdentities: {
      '${vmIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v3' // ⚠️ รุ่นประหยัดสุด (ถูกมาก/ฟรีสำหรับ Student ในบาง region)
    }
    osProfile: {
      computerName: vmName
      adminUsername: 'azureuser'
      // ⚠️ ใน Lab จริงจัง เราควรใช้ SSH Key แต่เพื่อความง่ายในการทดสอบเบื้องต้น ผมจะให้ใช้ Password (แต่ไม่ Hardcode)
      // เนื่องจาก Bicep บังคับใส่ Password ถ้าไม่ใช้ SSH Key
      // ในทางปฏิบัติ เราจะรับ Password เป็น Parameter แบบ Secure String
      // แต่เพื่อให้ Deploy ผ่านง่ายๆ ใน Lab นี้ ผมจะขออนุญาต Hardcode ชั่วคราว (Don't do this in Prod!)
      adminPassword: 'Password1234!' 
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
          storageAccountType: 'Standard_LRS' // ดิสก์แบบถูกสุด
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
        enabled: true // เปิดดูหน้าจอ console ได้ตอน boot ไม่ติด
      }
    }
  }
}

output vmId string = vm.id
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
