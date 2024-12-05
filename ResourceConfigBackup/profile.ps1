# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#

Set-Variable -Name StorageTokenUrl -Value $env:StorageBlobEndpoint -Option Constant
Set-Variable -Name LoginUrl -Value $env:LoginUrl -Option Constant
Set-Variable -Name MicrosoftGraphUrl -Value $env:GraphUrl -Option Constant
Set-Variable -Name ResourceManagerUrl -Value $env:ResourceManagerUrl -Option Constant

If ($env:debug -eq 'true') {
    $ErrorActionPreference = 'Continue'
    $WarningPreference = 'Continue'
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'
    $DebugPreference = 'SilentlyContinue'
    $ProgressPreference = 'Continue'
    $LogCommandHealthEvent = $false
    $LogCommandLifecycleEvent = $false
    $LogEngineHealthEvent = $true
    $LogEngineLifecycleEvent = $true
    $LogProviderHealthEvent = $true
    $LogProviderLifecycleEvent = $true
    $MaximumHistoryCount = 4096
    $PSDefaultParameterValues = @{
        "*:Verbose"           = $true
        "*:ErrorAction"       = 'Continue'
        "*:WarningAction"     = 'Continue'
        "*:InformationAction" = 'SilentlyContinue'
    }
}
Else {
    $ErrorActionPreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'
    $VerbosePreference = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'
    $DebugPreference = 'SilentlyContinue'
    $ProgressPreference = 'SilentlyContinue'
    $LogCommandHealthEvent = $false
    $LogCommandLifecycleEvent = $false
    $LogEngineHealthEvent = $false
    $LogEngineLifecycleEvent = $false
    $LogProviderHealthEvent = $false
    $LogProviderLifecycleEvent = $false
    $MaximumHistoryCount = 1
    $PSDefaultParameterValues = @{
        "*:Verbose"           = $false
        "*:ErrorAction"       = 'SilentlyContinue'
        "*:WarningAction"     = 'SilentlyContinue'
        "*:InformationAction" = 'SilentlyContinue'
    }
}

Function Invoke-AzureRestMethod {
    <#
        .SYNOPSIS
            Run an Azure REST call.
        .DESCRIPTION
            This is a modified version of Daniel Chronlund's Invoke-DCMsGraphQuery function. It will run a query against Microsoft REST APIs and return the result. It will connect using an access token generated by Connect-DCMsGraphAsDelegated or Connect-DCMsGraphAsApplication (depending on what permissions you use in Graph).
            This CMDlet will run a query against Microsoft REST APIs and return the result. It will connect using an access token generated by Connect-DCMsGraphAsDelegated or Connect-DCMsGraphAsApplication (depending on what permissions you use in Graph).
            Before running this CMDlet, you first need to register a new application in your Azure AD according to this article:
            https://danielchronlund.com/2018/11/19/fetch-data-from-microsoft-graph-with-powershell-paging-support/

        .PARAMETER AccessToken
                An access token generated by Connect-DCMsGraphAsDelegated or Connect-DCMsGraphAsApplication (depending on what permissions you use in Graph).
        .PARAMETER Method
                The HTTP method for the Graph call, like GET, POST, PUT, PATCH, DELETE. Default is GET.
        .PARAMETER Uri
                The Microsoft Graph URI for the query. Example: https://graph.microsoft.com/v1.0/users/
        .PARAMETER Body
                The request body of the Graph call. This is often used with methids like POST, PUT and PATCH. It is not used with GET.

        .INPUTS
            None
        .OUTPUTS
            None
        .NOTES
            Author:   Daniel Chronlund
            GitHub:   https://github.com/DanielChronlund/DCToolbox
            Blog:     https://danielchronlund.com/

        .EXAMPLE
            Invoke-AzureRestMethod -AccessToken $AccessToken -Method 'GET' -Uri 'https://graph.microsoft.com/v1.0/users/'
    #>

    param (
        [parameter(Mandatory = $true)]
        [string]$AccessToken,

        [parameter(Mandatory = $false)]
        [string]$Method = 'GET',

        [parameter(Mandatory = $true)]
        [string]$Uri,

        [parameter(Mandatory = $false)]
        [string]$Body = '',

        [parameter(Mandatory = $false)]
        [hashtable]$AdditionalHeaders
    )

    # Check if authentication was successfull.
    if ($AccessToken) {
        # Format headers.
        $HeaderParams = @{
            'Content-Type'  = "application\json"
            'Authorization' = "Bearer $AccessToken"
        }
        If ($AdditionalHeaders) {
            $HeaderParams += $AdditionalHeaders
        }

        # Create an empty array to store the result.
        $QueryRequest = @()
        $dataToUpload = @()

        # Run the first query.
        if ($Method -eq 'GET') {
            $QueryRequest = Invoke-RestMethod -Headers $HeaderParams -Uri $Uri -UseBasicParsing -Method $Method -ContentType "application/json" -Verbose:$false
        }
        else {
            $QueryRequest = Invoke-RestMethod -Headers $HeaderParams -Uri $Uri -UseBasicParsing -Method $Method -ContentType "application/json" -Body $Body -Verbose:$false
        }
        if ($QueryRequest.value) {
            $dataToUpload += $QueryRequest.value
        }
        else {
            $dataToUpload += $QueryRequest
        }

        # Invoke REST methods and fetch data until there are no pages left.
        if ($Uri -notlike "*`$top*") {
            while ($QueryRequest.'@odata.nextLink' -and $QueryRequest.'@odata.nextLink' -is [string]) {
                $QueryRequest = Invoke-RestMethod -Headers $HeaderParams -Uri $QueryRequest.'@odata.nextLink' -UseBasicParsing -Method $Method -ContentType "application/json" -Verbose:$false
                $dataToUpload += $QueryRequest.value
            }
            While ($QueryRequest.nextLink -and $QueryRequest.nextLink -is [string]) {
                $QueryRequest = Invoke-RestMethod -Headers $HeaderParams -Uri $QueryRequest.'nextLink' -UseBasicParsing -Method $Method -ContentType "application/json" -Verbose:$false #4>$null
                $dataToUpload += $QueryRequest.value
            }
            While ($QueryRequest.'$skipToken' -and $QueryRequest.'$skipToken' -is [string] -and $Body -ne '') {
                $tempBody = $Body | ConvertFrom-Json -AsHashtable
                $tempBody.'$skipToken' = $QueryRequest.'$skipToken'
                $Body = $tempBody | ConvertTo-Json -Depth 99
                $QueryRequest = Invoke-RestMethod -Headers $HeaderParams -Uri $Uri -UseBasicParsing -Method $Method -ContentType "application/json" -Body $Body -Verbose:$false #4>$null
                $dataToUpload += $QueryRequest.data
            }
        }
        $dataToUpload
    }
    else {
        Write-Error "No Access Token"
    }
}

function Connect-AcquireToken {
    <#
    .SYNOPSIS
    Connects to Azure AD and acquires an access token for the specified token resource URL.

    .DESCRIPTION
    The Connect-AcquireToken function connects to Azure AD and acquires an access token for the specified token resource URL. It supports both managed identity and service principal authentication methods.

    .PARAMETER ResourceManagerUrl
    The URL of the token resource for which to acquire the access token. The default value is $MicrosoftGraphUrl.

    .EXAMPLE
    Connect-AcquireToken -ResourceManagerUrl "https://graph.microsoft.com"
    This example connects to Azure AD and acquires an access token for the Microsoft Graph API.

    .INPUTS
    None

    .OUTPUTS
    System.String

    .NOTES
    This function requires the Azure PowerShell module to be installed.

    .LINK
    https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-12.0.0
    #>
    [CmdletBinding()]
    param (
        [string]$tokenResourceURL = $MicrosoftGraphUrl
    )

    if ($env:MSI_ENDPOINT) {
        return Connect-AcquireTokenViaManagedIdentity -ResourceManagerUrl $tokenResourceURL
    }
    Else {
        Write-Error "No Managed Identity"
    }

    #return Connect-AcquireTokenViaServicePrincipal -ResourceManagerUrl $ResourceManagerUrl
}

function Connect-AcquireTokenViaManagedIdentity {
    [CmdletBinding()]
    param (
        [string]$ResourceManagerUrl = $MicrosoftGraphUrl
    )
    $endpoint = $env:MSI_ENDPOINT
    $secret = $env:MSI_SECRET
    
    $accessTokenHeader = @{
        Secret = $secret
    }
    $OAuthUri = "$($endpoint)?api-version=2017-09-01&resource=$($ResourceManagerUrl)"
    
    $OAuth = Invoke-RestMethod -Method Get -Uri $OAuthUri -Headers $accessTokenHeader

    # Return the access token.
    $OAuth.access_token
}

function Upload-ToBlob {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]
        $ConnectionStringURI,
        [parameter(Mandatory = $false)]
        [string]
        $Path = {
            $myUTC = ([datetime]::UtcNow).tostring('yyyy-MM-ddTHH:mm:ss')
            $tzUTC = [system.timezoneinfo]::GetSystemTimeZones() | Where-Object { $_.id -eq 'UTC' }
            $tzEST = [system.timezoneinfo]::GetSystemTimeZones() | Where-Object { $_.id -eq 'US Eastern Standard Time' }
            $now = [System.TimeZoneInfo]::ConvertTime($myUTC, $tzUTC, $tzEST)
            "y=$($now.tostring('yyyy'))/m=$($now.tostring('MM'))/d=$($now.tostring('dd'))/h=$($now.tostring('HH'))/m=$($now.tostring('mm'))"
        },
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $filename,
        [parameter(Mandatory = $false)]
        [string]
        $timestamp = [datetime]::UtcNow.tostring('yyyy-MM-dd_HHmmss'),
        [parameter(Mandatory = $false)]
        $dataToUpload = '',
        [parameter(Mandatory = $false)]
        $infile = '',
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $storageToken,
        [parameter(Mandatory = $false)]
        [ValidateSet('json', 'csv', 'zip', 'txt')]
        [string]
        $extension = 'json',
        [parameter(Mandatory = $false)]
        [hashtable]
        $metadata
    )
    If ([string]::IsNullOrEmpty($dataToUpload)) { $dataToUpload = ' ' }
    $blobname = If ([string]::IsNullOrEmpty($Path)) { "$($filename)_$timestamp.$extension" }Else { "$Path/$($filename)_$timestamp.$extension" }
    $filestring = "$($timestamp)_$filename.$extension"
    
    If ($extension -eq 'csv') {
        $ContentType = 'text/csv; charset=UTF-8'
        If ([string]::IsNullOrEmpty($dataToUpload)) {
            Write-Warning "No results - so no CSV created"
        }
        Else {
            $body = ($dataToUpload | ConvertTo-Csv -NoTypeInformation) -join "`n"
        }
    }
    ElseIf ($extension -eq 'txt') {
        $ContentType = 'text/plain; charset=UTF-8'
        If ([string]::IsNullOrEmpty($dataToUpload)) {
            Write-Warning "No results - so no txt file created."
        }
        Else {
            $body = $dataToUpload
        }

    }
    ElseIf ($extension -eq 'zip') {
        $ContentType = 'application/zip'
        $body = $dataToUpload
    }
    Else {
        $ContentType = 'application/json; charset=UTF-8'
        $body = $dataToUpload | ConvertTo-Json -Depth 99
    }
    #Upload to storage 
    Write-Verbose -Message "$filename : Uploading $filestring to $ConnectionStringURI" -Verbose:$VerbosePreference
    $ConnectionStringAll = $ConnectionStringURI + "/" + $blobname
    $headers = @{
        'Content-Type'   = $ContentType
        'x-ms-blob-type' = 'BlockBlob'
        'authorization'  = "Bearer $storageToken"
        'x-ms-version'   = '2020-04-08'
        'x-ms-date'      = $([datetime]::UtcNow.tostring('ddd, dd MMM yyyy HH:mm:ss ') + 'GMT')
    } 

    If ($infile) {
        $body = [System.IO.File]::ReadAllBytes($infile)
        $headers.Remove('Content-Type')
        $headers.Add('Content-Length', $body.Length)
        $Null = Invoke-WebRequest -Uri $ConnectionStringAll -Method PUT -Headers $headers -Body $body -InFile $infile -UseBasicParsing
    }
    Else {
        $Null = Invoke-WebRequest -Uri $ConnectionStringAll -Method PUT -Headers $headers -Body $body -ContentType $ContentType -UseBasicParsing
    }
}

Function Get-ResourceGroupREST {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [parameter(Mandatory = $false)]
        [string]$ResourceGroupName
    )

    $resourceManagerToken = Connect-AcquireToken -TokenResourceUrl $ResourceManagerUrl
    #$resourceManagerToken = (Get-AzAccessToken -ResourceUrl $ResourceManagerUrl).token
    If ($ResourceGroupName) {
        $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resourceGroups/$($ResourceGroupName)?api-version=2014-04"
    }
    Else {
        $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resourceGroups?api-version=2014-04"
    }
    #    $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resourceGroups/$($ResourceGroupName)?api-version=2014-04"
    $resourceGroup = Invoke-AzureRestMethod -AccessToken $resourceManagerToken -Uri $uri -Method Get
    $resourceGroup
}


Function Get-SubscriptionsREST {
    [CmdletBinding()]
    param ()

    $resourceManagerToken = Connect-AcquireToken -TokenResourceUrl $ResourceManagerUrl
    #$resourceManagerToken = (Get-AzAccessToken -ResourceUrl $ResourceManagerUrl).token
    $uri = "$resourceManagerUrl/subscriptions?api-version=2016-06-01"
    $subscriptions = Invoke-AzureRestMethod -AccessToken $resourceManagerToken -Uri $uri -Method Get
    $subscriptions
}

Function Get-ResourcesREST {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [parameter(Mandatory = $false)]
        [string]$ResourceGroupName
    )

    $resourceManagerToken = Connect-AcquireToken -TokenResourceUrl $ResourceManagerUrl
    #$resourceManagerToken = (Get-AzAccessToken -ResourceUrl $ResourceManagerUrl).token
    If ($ResourceGroupName) {
        $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resourceGroups/$($ResourceGroupName)/resources?api-version=2016-09-01"
    }
    Else {
        $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resources?api-version=2016-09-01"
    }
    $resources = Invoke-AzureRestMethod -AccessToken $resourceManagerToken -Uri $uri -Method Get
    $resources
}

function Get-RoleAssignmentsREST {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [parameter(Mandatory = $false)]
        [string]$ResourceGroupName
    )

    $resourceManagerToken = Connect-AcquireToken -TokenResourceUrl $ResourceManagerUrl
    #$resourceManagerToken = (Get-AzAccessToken -ResourceUrl $ResourceManagerUrl).token
    If ($ResourceGroupName) {
        $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resourceGroups/$($ResourceGroupName)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
    }
    Else {
        $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2015-07-01"
    }
    $roleAssignments = Invoke-AzureRestMethod -AccessToken $resourceManagerToken -Uri $uri -Method Get
    $roleAssignments
}

Function Get-TemplateForResourcesREST {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [parameter(Mandatory = $false)]
        [array]$Resources
    )

    $resourceManagerToken = Connect-AcquireToken -TokenResourceUrl $ResourceManagerUrl
    #$resourceManagerToken = (Get-AzAccessToken -ResourceUrl $ResourceManagerUrl).token
    If ($Resources -eq $null) {
        $Resources = @('*')
    }
    
    $body = @{
        options   = 'IncludeParameterDefaultValue'
        resources = $Resources
    } | ConvertTo-Json
    $uri = "$resourceManagerUrl/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/exportTemplate?api-version=2018-08-01"
    $template = Invoke-AzureRestMethod -Uri $uri -Method Post -Body $body -AccessToken $resourceManagerToken   
    $template
}