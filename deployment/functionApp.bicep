@description('The name of the function app that you wish to create.')
param functionAppName string = 'fnapp${uniqueString(resourceGroup().id)}'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The Log Analytics workspace resource ID.')
param logAnalyticsWorkspaceResourceId string

@description('The package URI for the function app.')
param packageUri string = 'https://github.com/PaulHCode/AzureResourceConfigurationBackup/raw/refs/heads/main/ResourceConfigBackup/ResourceConfigBackup.zip'

@description('The PowerShell version')
param powerShellVersion string = '7.4'

var appSettings = union(
  [
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
      name: 'FUNCTIONS_WORKER_RUNTIME'
      value: 'powershell'
    }
    {
      name: 'EnvironmentName'
      value: environment().name
    }
    {
      name: 'GraphUrl'
      value: endsWith(environment().graph, '/')
        ? substring(environment().graph, 0, length(environment().graph) - 1)
        : environment().graph
    }
    {
      name: 'ResourceManagerUrl'
      // This workaround is needed because the environment().resourceManager value is missing the trailing slash for some Azure environments
      value: endsWith(environment().resourceManager, '/')
        ? substring(environment().resourceManager, 0, length(environment().resourceManager) - 1)
        : environment().resourceManager
    }
    {
      name: 'LoginUrl'
      value: endsWith(environment().authentication.loginEndpoint, '/')
        ? substring(
            environment().authentication.loginEndpoint,
            0,
            length(environment().authentication.loginEndpoint) - 1
          )
        : environment().authentication.loginEndpoint
    }
    {
      name: 'ResourceConfigOutputURL'
      value: '${storageAccount.properties.primaryEndpoints.blob}${resourceConfigContainerNames[0]}'
    }
    {
      name: 'StorageBlobEndpoint'
      value: endsWith(storageAccount.properties.primaryEndpoints.blob, '/')
        ? substring(
            storageAccount.properties.primaryEndpoints.blob,
            0,
            length(storageAccount.properties.primaryEndpoints.blob) - 1
          )
        : storageAccount.properties.primaryEndpoints.blob
    }
  ],
  !empty(logAnalyticsWorkspaceResourceId)
    ? [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
      ]
    : []
)

var cloudSuffix = replace(replace(environment().resourceManager, 'https://management.', ''), '/', '')
var hostingPlanName = functionAppName
var applicationInsightsName = functionAppName
var storageAccountName = replace(replace(toLower(take('${functionAppName}${uniqueString(resourceGroup().id, functionAppName)}', 24)), '-', ''), '_', '')
var resourceConfigContainerNames = [
  'backup'
  'resourceconfigrestoreinput'
]

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
  for containerName in resourceConfigContainerNames: {
    name: containerName
    parent: storageAccount::blobServices
    properties: {
      publicAccess: 'None'
    }
  }
]

resource storageAccount_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: '${storageAccountName}-diagnosticSettings'
  properties: {
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceResourceId
  }
  scope: storageAccount
}

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
      appSettings: appSettings
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

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspaceResourceId
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
