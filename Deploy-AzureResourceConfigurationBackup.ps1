[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [TypeName('System.String')]
    $Location
)

New-AzResourceGroupDeployment -ResourceGroupName 'AzureResourceConfigurationBackup' -TemplateFile "$PSScriptRoot\deployment\functionApp.json" -TemplateParameterFile "$PSScriptRoot\deployment\functionApp.parameters.json" -Location $Location