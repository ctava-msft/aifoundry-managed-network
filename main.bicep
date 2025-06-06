metadata description = 'AI Foundry workspace with managed network and private endpoints'

@description('The principal ID of the user to assign roles to')
param userPrincipalId string

@description('Skip creating role assignments if they already exist')
param skipRoleAssignments bool = true

@description('Array of IP addresses or CIDR blocks to allow access to storage and other services')
@metadata({
  description: 'Provide valid IPv4 addresses in CIDR notation (e.g., "203.0.113.0/24") or individual IPs (e.g., "203.0.113.1"). Do not include private IP ranges or invalid formats.'
})
param allowedIpAddresses array = []

@description('Timestamp for the deployment to ensure unique role assignment names')
param deploymentTimestamp string = utcNow()

var deploymentTimestamp_var = deploymentTimestamp
var allowedIpAddresses_var = allowedIpAddresses
var aiServicesName = 'ais-${uniqueSuffix}'
var keyVaultName = 'kv-${uniqueSuffix}'
var location = resourceGroup().location
var searchServiceName = 'search-${uniqueSuffix}'
var storageAccountName = 'sa${uniqueSuffix}'
var storageContainerName = 'sc${uniqueSuffix}'
var tenantId = subscription().tenantId
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 5)
var virtualNetworkName = 'vnet-${uniqueSuffix}'
var workspaceName = 'w-${uniqueSuffix}'
var projectName = 'p-${uniqueSuffix}'
var azureOpenAIConnectionName = '${workspaceName}-connection-AzureOpenAI'
var azureAISearchConnectionName = '${workspaceName}-connection-AzureAISearch'
var gptDeploymentName = 'gpt-4o-mini'
var privateEndpoints = {
  aiHub: 'pe-aihub-${uniqueSuffix}'
  aiServices: 'pe-aiservices-${uniqueSuffix}'
  keyVault: 'pe-kv-${uniqueSuffix}'
  storageBlob: 'pe-storage-blob-${uniqueSuffix}'
  storageFile: 'pe-storage-file-${uniqueSuffix}'
  search: 'pe-search-${uniqueSuffix}'
}
var privateDnsZones = {
  azureml: 'privatelink.api.azureml.ms'
  notebooks: 'privatelink.notebooks.azure.net'
  cognitiveservices: 'privatelink.cognitiveservices.azure.com'
  openai: 'privatelink.openai.azure.com'
  aiservices: 'privatelink.services.ai.azure.com'
  blob: 'privatelink.blob.core.windows.net'
  file: 'privatelink.file.core.windows.net'
  search: 'privatelink.search.windows.net'
  vault: 'privatelink.vaultcore.azure.net'
}
var roleDefinitions = {
  cognitiveServicesOpenAIContributor: 'a001fd3d-188f-4b5d-821b-7da978bf7442'
  cognitiveServicesOpenAIUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  cognitiveServicesContributor: '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  searchServicesContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageFileDataPrivilegedContributor: '69566ab7-960f-475b-8e7c-b3118f30c6bd'
  azureMLDataScientist: 'f6c7c914-8db3-469d-8ca1-694a8f32e121'
}
var deploymentSuffix = substring(replace(replace(deploymentTimestamp_var, ':', ''), '-', ''), 0, 8)
var roleAssignmentSuffix = concat(uniqueSuffix, deploymentSuffix)

// Helper function to validate and format IP addresses
var validIpAddresses = filter(allowedIpAddresses_var, ip => !empty(ip) && !startsWith(ip, '10.') && !startsWith(ip, '192.168.') && !startsWith(ip, '172.'))

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: ((length(validIpAddresses) > 0) ? 'Enabled' : 'Disabled')
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: ((length(validIpAddresses) > 0)
        ? map(validIpAddresses, ip => {
            value: contains(ip, '/') ? ip : '${ip}/32'
            action: 'Allow'
          })
        : [])
    }
  }
}

resource storageAccountName_default_storageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${storageContainerName}'
  properties: {}
  dependsOn: [
    storageAccount
  ]
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    accessPolicies: []
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: ((length(validIpAddresses) > 0)
        ? map(validIpAddresses, ip => {
            value: contains(ip, '/') ? split(ip, '/')[0] : ip
          })
        : [])
    }
  }
}

resource workspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01-preview' = {
  name: workspaceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'hub'
  properties: {
    friendlyName: workspaceName
    keyVault: keyVault.id
    storageAccount: storageAccount.id
    publicNetworkAccess: 'Disabled'
    managedNetwork: {
      isolationMode: 'AllowInternetOutbound'
    }
  }
}

resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'standard'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'disabled'
    networkRuleSet: {
      ipRules: ((length(validIpAddresses) > 0)
        ? map(validIpAddresses, ip => {
            value: contains(ip, '/') ? split(ip, '/')[0] : ip
          })
        : [])
      bypass: 'AzureServices'
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2021-10-01' = {
  name: aiServicesName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: ((length(validIpAddresses) > 0)
        ? map(validIpAddresses, ip => {
            value: contains(ip, '/') ? split(ip, '/')[0] : ip
          })
        : [])
    }
  }
}

resource aiServicesName_gptDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: aiServices
  name: '${gptDeploymentName}'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
  }
  sku: {
    name: 'Standard'
    capacity: 10
  }
}

resource workspaceName_azureOpenAIConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01-preview' = {
  parent: workspace
  name: '${azureOpenAIConnectionName}'
  properties: {
    category: 'AzureOpenAI'
    target: 'https://${aiServicesName}.cognitiveservices.azure.com/'
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiServices.id
    }
  }
}

resource workspaceName_azureAISearchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01-preview' = {
  parent: workspace
  name: '${azureAISearchConnectionName}'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchServiceName}.search.windows.net/'
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
    }
  }
}

resource workspaceName_search_outbound 'Microsoft.MachineLearningServices/workspaces/outboundRules@2024-04-01-preview' = {
  parent: workspace
  name: 'search-outbound'
  properties: {
    type: 'PrivateEndpoint'
    destination: {
      serviceResourceId: searchService.id
      subresourceTarget: 'searchService'
      sparkEnabled: false
    }
    category: 'UserDefined'
  }
  dependsOn: [
    workspaceName_azureAISearchConnection
    privateEndpoints_search
  ]
}

resource workspaceName_aiservices_outbound 'Microsoft.MachineLearningServices/workspaces/outboundRules@2024-04-01-preview' = {
  parent: workspace
  name: 'aiservices-outbound'
  properties: {
    type: 'PrivateEndpoint'
    destination: {
      serviceResourceId: aiServices.id
      subresourceTarget: 'account'
      sparkEnabled: false
    }
    category: 'UserDefined'
  }
  dependsOn: [
    workspaceName_azureOpenAIConnection
    privateEndpoints_aiServices
  ]
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.1.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource privateDnsZones_azureml 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.azureml
  location: 'global'
}

resource privateDnsZones_notebooks 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.notebooks
  location: 'global'
}

resource privateDnsZones_cognitiveservices 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.cognitiveservices
  location: 'global'
}

resource privateDnsZones_openai 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.openai
  location: 'global'
}

resource privateDnsZones_aiservices 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.aiservices
  location: 'global'
}

resource privateDnsZones_blob 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.blob
  location: 'global'
}

resource privateDnsZones_file 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.file
  location: 'global'
}

resource privateDnsZones_search 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.search
  location: 'global'
}

resource privateDnsZones_vault 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones.vault
  location: 'global'
}

resource privateDnsZones_azureml_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.azureml}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: true
  }
  dependsOn: [
    privateDnsZones_azureml
  ]
}

resource privateDnsZones_notebooks_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.notebooks}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_notebooks
  ]
}

resource privateDnsZones_cognitiveservices_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.cognitiveservices}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_cognitiveservices
  ]
}

resource privateDnsZones_openai_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.openai}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_openai
  ]
}

resource privateDnsZones_aiservices_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.aiservices}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_aiservices
  ]
}

resource privateDnsZones_blob_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.blob}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_blob
  ]
}

resource privateDnsZones_file_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.file}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_file
  ]
}

resource privateDnsZones_search_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.search}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_search
  ]
}

resource privateDnsZones_vault_virtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${privateDnsZones.vault}/${virtualNetworkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZones_vault
  ]
}

resource privateEndpoints_aiHub 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: privateEndpoints.aiHub
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpoints.aiHub
        properties: {
          privateLinkServiceId: workspace.id
          groupIds: [
            'amlworkspace'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpoints_aiHub_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  name: '${privateEndpoints.aiHub}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-api-azureml-ms'
        properties: {
          privateDnsZoneId: privateDnsZones_azureml.id
        }
      }
      {
        name: 'privatelink-notebooks-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZones_notebooks.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoints_aiHub
  ]
}

resource privateEndpoints_aiServices 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: privateEndpoints.aiServices
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpoints.aiServices
        properties: {
          privateLinkServiceId: aiServices.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpoints_aiServices_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  name: '${privateEndpoints.aiServices}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-cognitiveservices-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_cognitiveservices.id
        }
      }
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_openai.id
        }
      }
      {
        name: 'privatelink-services-ai-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_aiservices.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoints_aiServices
  ]
}

resource privateEndpoints_storageBlob 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: privateEndpoints.storageBlob
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpoints.storageBlob
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpoints_storageBlob_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  name: '${privateEndpoints.storageBlob}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones_blob.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoints_storageBlob
  ]
}

resource privateEndpoints_storageFile 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: privateEndpoints.storageFile
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpoints.storageFile
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpoints_storageFile_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  name: '${privateEndpoints.storageFile}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones_file.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoints_storageFile
  ]
}

resource privateEndpoints_search 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: privateEndpoints.search
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpoints.search
        properties: {
          privateLinkServiceId: searchService.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpoints_search_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  name: '${privateEndpoints.search}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-search-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones_search.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoints_search
  ]
}

resource privateEndpoints_keyVault 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: privateEndpoints.keyVault
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpoints.keyVault
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpoints_keyVault_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  name: '${privateEndpoints.keyVault}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZones_vault.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoints_keyVault
  ]
}

resource searchServiceName_roleDefinitions_searchServicesContributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid(searchServiceName, roleDefinitions.searchServicesContributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchServicesContributor
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource searchServiceName_roleDefinitions_searchIndexDataContributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid(searchServiceName, roleDefinitions.searchIndexDataContributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchIndexDataContributor
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource searchServiceName_roleDefinitions_searchIndexDataReader_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid(searchServiceName, roleDefinitions.searchIndexDataReader, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchIndexDataReader
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource aiServicesName_roleDefinitions_cognitiveServicesOpenAIUser_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid(aiServicesName, roleDefinitions.cognitiveServicesOpenAIUser, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesOpenAIUser
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource aiServicesName_roleDefinitions_cognitiveServicesOpenAIContributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid(aiServicesName, roleDefinitions.cognitiveServicesOpenAIContributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesOpenAIContributor
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource aiServicesName_roleDefinitions_cognitiveServicesContributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid(aiServicesName, roleDefinitions.cognitiveServicesContributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesContributor
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource aiServicesName_roleDefinitions_contributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid(aiServicesName, roleDefinitions.contributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.contributor)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource storageAccountName_roleDefinitions_contributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid(storageAccountName, roleDefinitions.contributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.contributor)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource storageAccountName_roleDefinitions_storageBlobDataContributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid(storageAccountName, roleDefinitions.storageBlobDataContributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.storageBlobDataContributor
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource storageAccountName_roleDefinitions_storageFileDataPrivilegedContributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid(
    storageAccountName,
    roleDefinitions.storageFileDataPrivilegedContributor,
    userPrincipalId,
    roleAssignmentSuffix
  )
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.storageFileDataPrivilegedContributor
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource id_roleDefinitions_contributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  name: guid(resourceGroup().id, roleDefinitions.contributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.contributor)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource searchServiceName_aiservices_contributor_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid('${searchServiceName}-aiservices-contributor-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchIndexDataContributor
    )
    principalId: reference(aiServices.id, '2021-10-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceName_aiservices_reader_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid('${searchServiceName}-aiservices-reader-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchIndexDataReader
    )
    principalId: reference(aiServices.id, '2021-10-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceName_aiservices_searchcontrib_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid('${searchServiceName}-aiservices-searchcontrib-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchServicesContributor
    )
    principalId: reference(aiServices.id, '2021-10-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aiServicesName_search_contrib_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid('${aiServicesName}-search-contrib-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesContributor
    )
    principalId: reference(searchService.id, '2023-11-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aiServicesName_search_openai_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid('${aiServicesName}-search-openai-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesOpenAIContributor
    )
    principalId: reference(searchService.id, '2023-11-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountName_search_blob_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid('${storageAccountName}-search-blob-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.storageBlobDataContributor
    )
    principalId: reference(searchService.id, '2023-11-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountName_aiservices_blob_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid('${storageAccountName}-aiservices-blob-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.storageBlobDataContributor
    )
    principalId: reference(aiServices.id, '2021-10-01', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountName_workspace_blob_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid('${storageAccountName}-workspace-blob-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.storageBlobDataContributor
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountName_workspace_file_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: storageAccount
  name: guid('${storageAccountName}-workspace-file-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.storageFileDataPrivilegedContributor
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource project 'Microsoft.MachineLearningServices/workspaces@2024-04-01-preview' = {
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'project'
  properties: {
    friendlyName: projectName
    hubResourceId: workspace.id
    publicNetworkAccess: 'Disabled'
  }
}

resource projectName_roleDefinitions_azureMLDataScientist_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: project
  name: guid(projectName, roleDefinitions.azureMLDataScientist, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.azureMLDataScientist
    )
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource projectName_roleDefinitions_contributor_userPrincipalId_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: project
  name: guid(projectName, roleDefinitions.contributor, userPrincipalId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.contributor)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource aiServicesName_workspace_contrib_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid('${aiServicesName}-workspace-contrib-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesContributor
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aiServicesName_workspace_openai_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: aiServices
  name: guid('${aiServicesName}-workspace-openai-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.cognitiveServicesOpenAIContributor
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceName_workspace_contrib_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid('${searchServiceName}-workspace-contrib-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchServicesContributor
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceName_workspace_reader_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid('${searchServiceName}-workspace-reader-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchIndexDataReader
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceName_workspace_datacontrib_roleAssignmentSuffix 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  scope: searchService
  name: guid('${searchServiceName}-workspace-datacontrib-${roleAssignmentSuffix}')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitions.searchIndexDataContributor
    )
    principalId: reference(workspace.id, '2024-04-01-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output workspaceName string = workspaceName
output projectName string = projectName
output aiServicesName string = aiServicesName
output searchServiceName string = searchServiceName
output storageAccountName string = storageAccountName
output keyVaultName string = keyVaultName
output gptDeploymentName string = gptDeploymentName
output resourceGroupName string = resourceGroup().name
