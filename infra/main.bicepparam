using './main.bicep'

param namePrefix = 'novamart'
param location = 'eastus'
param sqlAdministratorLogin = 'novamartadmin'
// Export AZURE_SQL_ADMIN_PASSWORD only in the deployment shell; never commit it.
param sqlAdministratorPassword = readEnvironmentVariable('AZURE_SQL_ADMIN_PASSWORD')
param alertEmailAddress = 'replace-with-real-oncall@example.com'
