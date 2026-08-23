targetScope = 'subscription'

@description('Short lowercase prefix used in resource names.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'novamart'

param location string = 'eastus'
param sqlAdministratorLogin string

@secure()
param sqlAdministratorPassword string

@description('Real address used by the independent Azure Monitor action group.')
param alertEmailAddress string

@description('Deploy both isolated environments. PROD ADF is intentionally not Git-linked.')
param environments array = [
  'dev'
  'prod'
]

resource resourceGroups 'Microsoft.Resources/resourceGroups@2024-03-01' = [for env in environments: {
  name: 'rg-${namePrefix}-${env}'
  location: location
  tags: {
    application: 'NovaMart Data Platform'
    environment: toUpper(env)
    managedBy: 'Bicep'
  }
}]

module platforms 'platform.bicep' = [for (env, index) in environments: {
  name: 'novamart-${env}'
  scope: resourceGroups[index]
  params: {
    namePrefix: namePrefix
    environmentName: env
    location: location
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorPassword: sqlAdministratorPassword
    alertEmailAddress: alertEmailAddress
  }
}]

output environments array = [for (env, index) in environments: {
  environment: env
  resourceGroup: resourceGroups[index].name
  dataFactoryName: platforms[index].outputs.dataFactoryName
  storageAccountName: platforms[index].outputs.storageAccountName
  sqlServerName: platforms[index].outputs.sqlServerName
  sqlDatabaseName: platforms[index].outputs.sqlDatabaseName
  keyVaultName: platforms[index].outputs.keyVaultName
  logicAppName: platforms[index].outputs.logicAppName
  logAnalyticsWorkspaceName: platforms[index].outputs.logAnalyticsWorkspaceName
}]
