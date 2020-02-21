param 
(
    [string]$ARMOutput,
    [string]$workspaceName,
    [string]$workspaceRG,
    [string]$tenantId,
    [string]$servicePrincipalId,
    [string]$servicePrincipalKey,
    [string]$subscriptionId
)

function Get-AzureRestAuthHeader
{
    param
    (
        [string]$tenantId,
        [string]$servicePrincipalId,
        [string]$servicePrincipalKey
    )

    $EncServicePrincipalId = [System.Net.WebUtility]::UrlEncode($servicePrincipalId)
    $EncServicePrincipalKey = [System.Net.WebUtility]::UrlEncode($servicePrincipalKey)
    $securePassword = ConvertTo-SecureString $servicePrincipalKey -AsPlainText -Force
    $psCredential = New-Object System.Management.Automation.PSCredential ($servicePrincipalId, $securePassword)
    Add-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential | Out-Null

    $ARMResource = "https://management.core.windows.net/"
    $EncARMResource = [System.Net.WebUtility]::UrlEncode($ARMResource)
    [string]$address = "https://login.windows.net/$tenantId/oauth2/token"
    $SPNPayload = "resource=$EncARMResource&client_id=$EncServicePrincipalId&grant_type=client_credentials&client_secret=$EncServicePrincipalKey";

    $httpClient = New-Object "System.Net.Http.HttpClient"

    $content = New-Object System.Net.Http.StringContent($SPNPayload,[System.Text.Encoding]::UTF8,"application/x-www-form-urlencoded")

    $response = $httpClient.PostAsync($address, $content)

    if($response.Result.IsSuccessStatusCode -eq $true)
    {
        $body = $response.Result.Content.ReadAsStringAsync()
        $JsonBody = $body.Result | ConvertFrom-Json
        $accessToken = $JsonBody.access_token
    }

    $header = @{
        'Content-Type'='application\json'
        'Authorization'="Bearer $accesstoken"
    }

    return $header
}

Write-Host $workspaceRG
Write-Host $workspaceName
Write-Host $tenantId
Write-Host $subscriptionId
Write-Host $servicePrincipalId
Write-Host $servicePrincipalKey

$header = Get-AzureRestAuthHeader -tenantId $tenantId -servicePrincipalId $servicePrincipalId -servicePrincipalKey $servicePrincipalKey

#Write-Host $header

Select-AzSubscription -SubscriptionID $subscriptionID

$SavedSearch = Get-AzOperationalInsightsSavedSearch -ResourceGroupName $workspaceRG -WorkspaceName $workspaceName

$UpdatesSearch = $SavedSearch.Value | Where-Object {$_.Id -match "MicrosoftDefaultComputerGroup" -and $_.Properties.Category -eq "Updates"}
$UpdatesQuery = $UpdatesSearch.Properties.query

Write-Host "Current Updates Query: $UpdatesQuery"

$ChangeTrackingSearch = $SavedSearch.Value | Where-Object {$_.Id -match "MicrosoftDefaultComputerGroup" -and $_.Properties.Category -eq "ChangeTracking"}
$ChangeTrackingQuery = $ChangeTrackingSearch.Properties.query

Write-Host "Current ChangeTracking Query: $ChangeTrackingQuery"

$Start = $UpdatesQuery.IndexOf("(")+1
$UpdatesOnboardedVMs = ($UpdatesQuery.Substring($Start,$UpdatesQuery.IndexOf("or")-($Start+2))).Replace('"','').Split(",").Trim()
#$UpdatesOnboardedVMs = $UpdatesVMString.Replace('"','').Split(",")

Write-Host "UpdatesOnboardedVMs: $UpdatesOnboardedVMs"

$Start = $ChangeTrackingQuery.IndexOf("(")+1
$ChangeTrackingOnboardedVMs = ($ChangeTrackingQuery.Substring($Start,$ChangeTrackingQuery.IndexOf("or")-($Start+2))).Replace('"','').Split(",").Trim()
#$ChangeTrackingOnboardedVMs = $ChangeTrackingVMString.Replace('"','').Split(",")

Write-Host "ChangeTrackingOnboardedVMs: $ChangeTrackingOnboardedVMs"

#region Convert from json
$ARMOutputJson = $ARMOutput | ConvertFrom-Json
#endregion

#region Parse ARM Template Output
$vmDetails = $ARMOutputJson.vmdetails.value
$vmNames = $vmDetails.vmName

Write-Host "VMs Deployed with Current ARM Template: $vmNames"

$UpdatesVMString = $null
$ChangeTrackingVMString = $null
$newUpdateVMs = $false
$newChangeTrackingVMs = $false

foreach($vm in $vmNames)
{
    if(!($vm -in $UpdatesOnboardedVMs))
    {
        $newUpdateVMs = $true
        $UpdatesVMString += "`"$vm`", "
        #Write-Host $UpdatesVMString
    }

    if(!($vm -in $ChangeTrackingOnboardedVMs))
    {
        $newChangeTrackingVMs = $true
        $changeTrackingVmString += "`"$vm`", "
        Write-Host $ChangeTrackingVMString
    }
}

if($newUpdateVMs)
{
    $UpdatesVMString = $UpdatesVMString.TrimEnd(', ')
    $UpdatesNewQuery = $UpdatesQuery.Replace('Computer in~ (',"Computer in~ ($UpdatesVMString, ")

    $BodyString = @{
        "properties" = @{
            "category"   = "Updates"
            "displayName" = "MicrosoftDefaultComputerGroup"
            "query" = $UpdatesNewQuery
            "version" = 2
            "tags" = @(
                @{
                    "Name" = "Group"
                    "Value" = "Computer"
                }
            )
            "FunctionAlias" = "Updates__MicrosoftDefaultComputerGroup"
        }
    } | ConvertTo-Json -Depth 99

    $UpdatesSearchID = "updates|microsoftdefaultcomputergroup"
    Remove-AzOperationalInsightsSavedSearch -ResourceGroupName $workspaceRG -WorkspaceName $workspaceName -SavedSearchId $UpdatesSearchID

    Write-Host $BodyString

    Write-Host "Onboarding New VMs to Azure Automation Update Management"
    #Invoke-RestMethod -Method Get -Headers $header "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$workspaceRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/savedSearches/$($UpdatesSearchID)?api-version=2015-03-20" -Verbose
    Invoke-RestMethod -Method PUT -Headers $header "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$workspaceRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/savedSearches/$($UpdatesSearchID)?api-version=2015-03-20" -Body $BodyString -ContentType "application/json" -Verbose
}

if($newChangeTrackingVMs)
{
    $ChangeTrackingVMString = $ChangeTrackingVMString.TrimEnd(', ')
    $ChangeTrackingNewQuery = $ChangeTrackingQuery.Replace('Computer in~ (',"Computer in~ ($ChangeTrackingVMString, ")

    $BodyString = @{
        "properties" = @{
            "category"   = "ChangeTracking"
            "displayName" = "MicrosoftDefaultComputerGroup"
            "query" = $ChangeTrackingNewQuery
            "version" = 2
            "tags" = @(
                @{
                    "Name" = "Group"
                    "Value" = "Computer"
                }
            )
            "FunctionAlias" = "ChangeTracking__MicrosoftDefaultComputerGroup"
        }
    } | ConvertTo-Json -Depth 99

    $ChangeTrackingSearchID = "changetracking|microsoftdefaultcomputergroup"
    Remove-AzOperationalInsightsSavedSearch -ResourceGroupName $workspaceRG -WorkspaceName $workspaceName -SavedSearchId $ChangeTrackingSearchID

    Write-Host $BodyString

    Write-Host "Onboarding New VMs to Azure Automation Change Tracking"
    #Invoke-RestMethod -Method GET -Headers $header "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$workspaceRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/savedSearches/$($ChangeTrackingSearchID)?api-version=2015-03-20"
    Invoke-RestMethod -Method PUT -Headers $header "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$workspaceRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/savedSearches/$($ChangeTrackingSearchID)?api-version=2015-03-20" -Body $BodyString -ContentType "application/json" -Verbose

}