<#

Script Prerequisites:
    1. Service Principal Exists
    2. Key Vault Exists with Correct Secret Access Policies for Service Principal (Get, Set, List)
    3. Storage Account for storing Logs Already Exists  
    4. App Service Already Exists

Script Steps:

    1. Gets a Rest Header to use for making direct Azure REST API calls using an Azure Service Principal.   
    2. Initializes logging containers for the storage Account Passed In
        i.	Application logs
        ii.	Http Logs
    3. For each container, checks for existence of existing SASToken by checking Key Vault. If it does not exist:
            i.	Storage Access Policy is created
        ii.	SAS Token is created and uploaded to Key Vault.
    4. For each container, SAS Token is pulled from Key Vault
    5. JSON Payload is created for REST API Call using 2 SAS Tokens from above
    6. Rest API is called to deploy logging configuration.  
 
 #>

[CmdletBinding()]
param(
    [string]$appServiceName,
    [string]$storageAccountName,
    [string]$keyVaultName,
    [string]$RGName,
    [string]$subscriptionID,
    [string]$tenantId,
    [string]$servicePrincipalId,
    [string]$servicePrincipalKey
)

function Get-AzureRestAuthHeader {
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

    $content = New-Object System.Net.Http.StringContent($SPNPayload, [System.Text.Encoding]::UTF8, "application/x-www-form-urlencoded")

    $response = $httpClient.PostAsync($address, $content)

    if ($response.Result.IsSuccessStatusCode -eq $true) {
        $body = $response.Result.Content.ReadAsStringAsync()
        $JsonBody = $body.Result | ConvertFrom-Json
        $accessToken = $JsonBody.access_token
    }

    $header = @{
        'Content-Type'  = 'application\json'
        'Authorization' = "Bearer $accesstoken"
    }

    return $header
}

$header = Get-AzureRestAuthHeader -tenantId $tenantId -servicePrincipalId $servicePrincipalId -servicePrincipalKey $servicePrincipalKey

Select-AzSubscription -Subscription $SubscriptionID

################# Create Azure Storage Container ###########################

#Set Current Storage Container
Set-AzCurrentStorageAccount -ResourceGroupName $RGName -StorageAccountName $storageAccountName

$containers = ("applicationlogs", "httplogs")

foreach ($container in $containers) {
    $currentcontainer = Get-AzStorageContainer -Name $container -ErrorAction SilentlyContinue

    #If exists, move to next step. If not, create container 
    If ($currentcontainer) {
        Write-Host "Container $container already exists. Moving to next step"
    }
    else {
        New-AzStorageContainer -Name $container
        Write-Host "Creating $container in storage account"
    }
    
    $ContainerSecretName = "$appServiceName$($container)SASTokenSecret"

    $ContainerSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName | where-object { $_.Name -eq $ContainerSecretName }

    if ($ContainerSecret) {
        Write-Host "Secret: $ContainerSecretName already exists"
    }
    else {
        $Policy = Get-AzStorageContainerStoredAccessPolicy -Container $container

        if (!$Policy) {
            $PolicyName = (Get-Date -Format "MM.dd.yyyy_HHmm") + $container		
            New-AzStorageContainerStoredAccessPolicy -Container $container -Policy $PolicyName -ExpiryTime $(Get-Date).AddYears(5) -Permission "rwdl"
        }
            
        $SASToken = New-AzStorageContainerSASToken -Name $container -Policy $PolicyName -Protocol HttpsOnly -FullUri
        $secSASToken = $SASToken | ConvertTo-SecureString -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $ContainerSecretName -SecretValue $secSASToken
    }

}

$AppLogsContainerSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "$($appServiceName)applicationlogsSASTokenSecret"
$AppLogsSASToken = $AppLogsContainerSecret.SecretValueText

$HttpLogsContainerSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "$($appServiceName)httplogsSASTokenSecret"
$HttpLogsSASToken = $HttpLogsContainerSecret.SecretValueText

$BodyString = @"
{"properties": {
    "applicationLogs": {
    "azureBlobStorage": {
        "level": "Information",
        "sasUrl": "$AppLogsSASToken",
        "retentionInDays": 365
    }
    },
    "httpLogs": {
    "azureBlobStorage": {
        "level": "Information",
        "sasUrl": "$HttpLogsSASToken",
        "retentionInDays": 365,
        "enabled": true
    }
    },
    "failedRequestsTracing": {
    "enabled": "true"
    },
    "detailedErrorMessages": {
    "enabled": "true"
    }
}
}
"@

Invoke-RestMethod -Method PUT -Headers $header "https://management.azure.com/subscriptions/$SubscriptionID/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($appServiceName)/config/logs?api-version=2019-08-01" -Body $BodyString -ContentType "application/json" -Verbose

