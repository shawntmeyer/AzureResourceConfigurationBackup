param($Timer)

#region Initialize Variables
$now = ([System.DateTime]::UtcNow) #.ToString("yyyy-MM-ddTHHmmss")
$timestamp = $now.tostring('yyyy-MM-ddTHHmmss')
$ConnectionStringUri = $env:ResourceConfigOutputURL
Write-Host "ConnectionString URI = $ConnectionStringURI"
$chunkSize = 200
$Path = "y=$($now.ToString('yyyy'))/m=$($now.ToString('MM'))/d=$($now.ToString('dd'))/h=$($now.ToString('HH'))/m=$($now.ToString('mm'))"
Write-Host "Path = $path"
$storageToken = Connect-AcquireToken -TokenResourceUrl $storageTokenUrl
$token = Connect-AcquireToken -TokenResourceUrl $resourceManagerUrl
$allSubscriptions = Get-SubscriptionsREST
#Write-Host "allSubscriptions = $($allSubscriptions | convertto-json -depth 99)"
#consider limiting scope later, but for now just get everything the MI has perms to get all subs
ForEach ($subscription in $allSubscriptions) {
    Write-Host "Processing subscription $($subscription.subscriptionId)"
    $allResourceGroups = Get-ResourceGroupREST -subscriptionId $subscription.subscriptionId
    #Write-Host "allResourceGroups = $($allResourceGroups | convertto-json -depth 99)"
    ForEach ($resourceGroup in $allResourceGroups) {
        #get all resources in each RG
        $allResourcesInResourceGroup = Get-ResourcesREST -subscriptionId $subscription.subscriptionId -resourceGroupName $resourceGroup.Name
        [array]$allResourcesInResourceGroup = $allResourcesInResourceGroup.Id
        #        write-host "allResourcesInResourceGroup = $($allResourcesInResourceGroup | convertto-json -depth 99)"
        $chunks = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $allResourcesInResourceGroup.count; $i += $chunkSize) {
            [void]$chunks.Add($allResourcesInResourceGroup[$i..($i + $chunkSize - 1)])
        }
        $resourcesInRG = @()
        #        write-host "chunks = $chunks"
        ForEach ($chunk in $chunks) {
            #            write-host "chunk = $chunk"
            $template = Get-TemplateForResourcesREST -subscriptionId $subscription.subscriptionId -resourceGroupName $resourceGroup.Name -resources $chunk
            #            Write-Host "template = $($template | ConvertTo-Json -Depth 99)"
            $template | Add-Member -MemberType NoteProperty -Name resourceGroup -Value $resourceGroup
            $resourcesInRG += $template
        }
        
        $filePath = $path + '/subscriptions/' + $subscription.subscriptionId + '/resourceGroups/' + $resourceGroup.Name
        $chunkCounter = 0
        ForEach ($templateChunk in $resourcesInRG) {
            $filename = $resourceGroup.Name + '_chunk' + $chunkCounter
            #           Write-Host "resourceGroup.Name = $($resourceGroup.Name)"
            #           Write-Host "filename = $filename"
            Upload-ToBlob -ConnectionStringUri $ConnectionStringUri -Path $filePath -fileName $filename -timestamp $timestamp -dataToUpload $templateChunk -storageToken $storageToken -extension 'json'
            $chunkCounter++
        }

        #get role assignments for everything in the RG
        $roleAssignments = Get-RoleAssignmentsREST -subscriptionId $subscription.subscriptionId -resourceGroupName $resourceGroup.Name
        $filename = 'roleAssignments'
        #       Write-Host "filename = $filename"
        Upload-ToBlob -ConnectionStringUri $ConnectionStringUri -Path $filePath -fileName $filename -timestamp $timestamp -dataToUpload $roleAssignments -storageToken $storageToken -extension 'json'
    }

    #get role assignments for everything in the subscription
    $roleAssignments = Get-RoleAssignmentsREST -subscriptionId $subscription.subscriptionId
    $filePath = $path + '/subscriptions/' + $subscription.subscriptionId
    $filename = 'roleAssignments'
    #    Write-Host "filename = $filename"
    Upload-ToBlob -ConnectionStringUri $ConnectionStringUri -Path $filePath -fileName $filename -timestamp $timestamp -dataToUpload $roleAssignments -storageToken $storageToken -extension 'json'
    
}

Write-Host ("Azure Resource Configurations are exported to " + $ConnectionStringURI)