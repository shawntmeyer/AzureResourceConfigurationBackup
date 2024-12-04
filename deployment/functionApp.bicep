@description('The name of the function app that you wish to create.')
param functionAppName string = 'fnapp${uniqueString(resourceGroup().id)}'

@description('Location for all resources.')
param location string = resourceGroup().location

param packageUri string = 'https://raw.githubusercontent.com/shawntmeyer/SentinelSync/refs/heads/main/SentinelSyncFA.zip'

@description('The PowerShell version')
param powerShellVersion string = '7.4'

@description('The Sentinel Workspace Name')
param sentinelWorkspaceName string

@description('The Sentinel Subscription Id')
param sentinelSubscriptionId string = subscription().subscriptionId

@description('The Sentinel Resource Group Name')
param sentinelResourceGroupName string

var cloudSuffix = replace(replace(environment().resourceManager, 'https://management.', ''), '/', '')
var hostingPlanName = functionAppName
var applicationInsightsName = functionAppName
var storageAccountName = toLower(take('${functionAppName}${uniqueString(resourceGroup().id, functionAppName)}', 24))
var sentinelAnalyticsContainerNames = [
  'sentinelanalyticsinput'
  'sentinelanalyticsoutput'
]

resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' existing = {
  name: sentinelWorkspaceName
  scope: resourceGroup(sentinelSubscriptionId, sentinelResourceGroupName)
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
  resource blobServices 'blobServices' = {
    name: 'default'
  }
}

resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [
  for containerName in sentinelAnalyticsContainerNames: {
    name: containerName
    parent: storageAccount::blobServices
    properties: {
      publicAccess: 'None'
    }
  }
]

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~14'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'SentinelResourceId'
          value: sentinel.id
        }
        {
          name: 'LogAnalyticsResourceId'
          value: sentinel.properties.workspaceResourceId
        }
        {
          name: 'SentinelAnalyticsOutputUrl'
          value: '${storageAccount.properties.primaryEndpoints.blob}${sentinelAnalyticsContainerNames[1]}'
        }
      ]
      cors: {
        allowedOrigins: [
          '${environment().portal}'
          'https://functions-next.${cloudSuffix}'
          'https://functions-staging.${cloudSuffix}'
          'https://functions.${cloudSuffix}'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      powerShellVersion: powerShellVersion
    }
    httpsOnly: true
  }
}

resource functions 'Microsoft.Web/sites/extensions@2023-12-01' = {
  #disable-next-line BCP088
  name: 'ZipDeploy'
  parent: functionApp
  properties: {
    packageUri: packageUri
    appOffline: false
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: sentinel.properties.workspaceResourceId
  }
}

module roleAssignmentStorageAccount 'modules/roleAssignment-storageAccount.bicep' = {
  name: 'roleAssignment-storageAccount'
  params: {
    principalId: functionApp.identity.principalId
    storageAccountResourceId: storageAccount.id
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Contributor
  }
}

module logAnalyticsSentinelContributorRoleAssignment 'modules/roleAssignment-logAnalyticsWorkspace.bicep' = {
  name: 'roleAssignment-logAnalyticsWorkspace'
  scope: resourceGroup(sentinelSubscriptionId, sentinelResourceGroupName)
  params: {
    principalId: functionApp.identity.principalId
    logAnalyticsWorkspaceId: sentinel.properties.workspaceResourceId
    roleDefinitionId: 'ab8e14d6-4a74-4a29-9ba8-549422addade' // Sentinel Contributor role'
  }
}

