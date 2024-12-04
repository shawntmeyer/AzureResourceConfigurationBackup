param([byte[]] $InputBlob, $TriggerMetadata)

Write-Host "PowerShell Blob trigger function Processed blob! Name: $($TriggerMetadata.BlobTrigger) Size: $($BlobTrigger.Length) bytes"

#region Initialize Variables
$now = [datetime]::UtcNow
$token = Connect-AcquireToken -TokenResourceUrl $resourceManagerUrl
#$token = (Get-AzAccessToken -ResourceUrl $resourceManagerUrl).token

#Get the info from the file
$blobContent = [System.Text.Encoding]::UTF8.GetString($InputBlob)

ForEach ($blob in $($blobContent | ConvertFrom-Json)) {
    $template = $blob.template | ConvertTo-Json -Depth 99 | ConvertFrom-Json -AsHashtable
    $subscriptionId = $blob.resourceGroup.id.Split('/')[2]
    $resourceGroupName = $blob.resourceGroup.Name

    $body = @{
        'properties' = @{
            'mode'     = 'Incremental'
            'template' = $template
        }
    } | ConvertTo-Json -Depth 99

    $deploymentId = [guid]::NewGuid().ToString()
    Write-Host "Attempting Deployment $deploymentId `t SubscriptionId: $subscriptionId `t ResourceGroupName: $resourceGroupName" -ForegroundColor Green
    $uri = "$resourceManagerUrl/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/Microsoft.Resources/deployments/$($deploymentId)?api-version=2020-10-01"
    $response = Invoke-AzureRestMethod -Uri $uri -Method Put -Body $body -AccessToken $token
    Write-Host "Created Deployment $($response.id)" -ForegroundColor Green
}
