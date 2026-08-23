targetScope = 'resourceGroup'

param namePrefix string
param environmentName string
param location string
param sqlAdministratorLogin string

@secure()
param sqlAdministratorPassword string

param alertEmailAddress string

var suffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id), 7)
var compactPrefix = replace(namePrefix, '-', '')
var storageName = take(toLower('st${compactPrefix}${environmentName}${suffix}'), 24)
var dataFactoryName = take(toLower('adf-${namePrefix}-${environmentName}-${suffix}'), 63)
var sqlServerName = take(toLower('sql-${namePrefix}-${environmentName}-${suffix}'), 63)
var keyVaultName = take(toLower('kv-${compactPrefix}-${environmentName}-${suffix}'), 24)
var logicAppName = take(toLower('la-${namePrefix}-failure-${environmentName}-${suffix}'), 60)
var workspaceName = take(toLower('log-${namePrefix}-${environmentName}-${suffix}'), 63)
var officeConnectionName = 'office365-${environmentName}'
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var storageBlobContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
  tags: {
    environment: toUpper(environmentName)
    workload: 'NovaMart'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
  }
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in [
  'landing'
  'output'
  'adf-copy-logs'
]: {
  parent: blobService
  name: containerName
  properties: { publicAccess: 'None' }
}]

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    environment: toUpper(environmentName)
    workload: 'NovaMart'
  }
}

resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: 'sqldb-novamart'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    environment: toUpper(environmentName)
    workload: 'NovaMart'
  }
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
var sqlConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${database.name};Persist Security Info=False;User ID=${sqlAdministratorLogin};Password=${sqlAdministratorPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

resource storageSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'adls-connection-string'
  properties: { value: storageConnectionString }
}

resource sqlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-connection-string'
  properties: { value: sqlConnectionString }
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    publicNetworkAccess: 'Enabled'
    globalParameters: {
      environment: { type: 'String', value: toUpper(environmentName) }
      logicAppCallbackUrl: { type: 'String', value: '__SET_AFTER_LOGIC_APP_DEPLOYMENT__' }
    }
  }
  tags: {
    environment: toUpper(environmentName)
    workload: 'NovaMart'
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, dataFactory.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, dataFactory.id, storageBlobContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobContributorRoleId
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
  tags: {
    environment: toUpper(environmentName)
    workload: 'NovaMart'
  }
}

resource factoryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-adf-runs-to-log-analytics'
  scope: dataFactory
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'PipelineRuns', enabled: true }
      { category: 'ActivityRuns', enabled: true }
      { category: 'TriggerRuns', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = {
  name: 'ag-${namePrefix}-data-oncall-${environmentName}'
  location: 'global'
  properties: {
    groupShortName: take('nm-${environmentName}-data', 12)
    enabled: true
    emailReceivers: [
      {
        name: 'DataOnCall'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

resource failedPipelineAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-adf-pipeline-failure-${environmentName}'
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: 'NovaMart ADF failed pipeline - ${toUpper(environmentName)}'
    description: 'Independent alert when one or more ADF pipelines fail in a five-minute window.'
    enabled: true
    severity: 1
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [workspace.id]
    criteria: {
      allOf: [
        {
          query: 'ADFPipelineRun | where Status == "Failed"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: officeConnectionName
  location: location
  properties: {
    displayName: 'NovaMart Office 365 - ${toUpper(environmentName)}'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}

resource failureLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: office365Connection.name
            id: office365Connection.properties.api.id
          }
        }
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': { type: 'Object', defaultValue: {} }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              required: ['emailAddress', 'subject', 'messageBody']
              properties: {
                emailAddress: { type: 'string' }
                subject: { type: 'string' }
                messageBody: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        Send_an_email: {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            host: {
              connection: { name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']' }
            }
            method: 'post'
            path: '/v2/Mail'
            body: {
              To: '@triggerBody()?[\'emailAddress\']'
              Subject: '@triggerBody()?[\'subject\']'
              Body: '@triggerBody()?[\'messageBody\']'
              Importance: 'High'
            }
          }
        }
        Response: {
          type: 'Response'
          runAfter: { Send_an_email: ['Succeeded'] }
          inputs: { statusCode: 202, body: { status: 'accepted' } }
        }
      }
      outputs: {}
    }
  }
  tags: {
    environment: toUpper(environmentName)
    workload: 'NovaMart'
  }
}

output dataFactoryName string = dataFactory.name
output storageAccountName string = storage.name
output sqlServerName string = sqlServer.name
output sqlDatabaseName string = database.name
output keyVaultName string = keyVault.name
output keyVaultUrl string = keyVault.properties.vaultUri
output logicAppName string = failureLogicApp.name
output logAnalyticsWorkspaceName string = workspace.name
