# Azure Resource Configuration Backup
This script will backup the configuration of Azure resources to a storage account. This script is intended to be run as an Azure Function App.

## Blue Button Deployment

| Deployment Type | Link |
|:--|:--|
| Azure portal UI |[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fshawntmeyer%2FAzureResourceConfigurationBackup%2Frefs%2Fheads%2Fmain%2Fdeployment%2FfunctionApp.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fshawntmeyer%2FAzureResourceConfigurationBackup%2Frefs%2Fheads%2Fmain%2Fdeployment%2FuiFormDefinition.json) [![Deploy to Azure Gov](https://aka.ms/deploytoazuregovbutton)](https://portal.azure.us/?feature.deployapiver=2022-12-01#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fshawntmeyer%2FAzureResourceConfigurationBackup%2Frefs%2Fheads%2Fmain%2Fdeployment%2FfunctionApp.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fshawntmeyer%2FAzureResourceConfigurationBackup%2Frefs%2Fheads%2Fmain%2Fdeployment%2FuiFormDefinition.json)

## Installation
The function app does not require any PowerShell modules however the script to deploy it currently assumes you have the following modules installed. I plan to remove this dependency in the future.
- Az.Accounts
- Az.Resources
- Az.Functions
- Az.OperationalInsights
- Az.Websites

Update the LogAnalyticsWorkspaceResourceId parameter value in [deployment\functionApp.parameters.json] file.

```PowerShell
    # Connect-AzAccount to the right tenant and set-azcontext to the right subscription first
   .\Deploy-AzureResourceConfigurationBackup.ps1 -Location '<region>'
```