# This script is designed to be executed as part of an Azure DevOps Pipeline in Azure PowerShell Script Task
#   1. Authentication to Azure occurs using Azure DevOps Service Connection
#   2. ServiceConnection should have the owner role in each Subscription provided in "SubscriptionIDList" parameter
#       * Owner is required for setting specific RBAC permissions for each AzDO Service Connection
#   3. Parameter List Explanation and Prerequisites:
#       a. KeyVaultName - Name of Azure Key Vault:
#           * The Service Connection needs Get,List,Set permissions to Secrets on the Key Vault
#           * Key Vault is used for: 
#               1) Storing the credentials for the new SPN and 
#               2) Retrieving the Az DevOps PAT Token for using the az devops cli: 
#                   https://docs.microsoft.com/en-us/azure/devops/cli/log-in-via-pat?view=azure-devops&tabs=windows
#               * The Az DevOps token needs to be generated and stored in Key Vault manually prior to script execution
#       b. SubscriptionIDList - List of Subscription IDs to create Resource Groups in for New Project
#       c. RGName - Name of the Resource Group to create in each Subscription
#       d. RGLocation - Azure Region to create each RG in.
#       e. azDevOpsPATSecretName - Name of Secret in Azure Key Vault where Az DevOps PAT Token is stored. (See 3a above)
#       f. azDevOpsOrgName - Name of Azure DevOps Organization where new Project should be created
#           *Az DevOps PAT (see 3a and 3e) needs to be created in this Organization.      
#       g. azDevOpsProjName - Name of new Az DevOps Project to be created inside Organization 
#
#   4. Script Execution:
#       PathToScript\OnboardProject_AzPS.ps1 -keyVaultName kvname -SubscriptionIDList id1,1d2 -RGName RGName -RGLocation RGLocation -azDevOpsOrgName AzDevOpsOrgName -azDevOpsProjName AzDevOpsProjName -azDevOpsPATSecretName SecretName

param
(
    [string]$keyVaultName,
    [array]$SubscriptionIDList,
    [string]$RGName,
    [string]$RGLocation,
    [string]$azDevOpsPATSecretName,
    [string]$azDevOpsOrgName,
    [string]$azDevOpsProjName
)

function GetPrefix
{
    #Use this function to provide the Prefix for your Az DevOps Service Connections
    #
    #The example shown here gets the name of the Evironment Type for the current Azure Subscription 
    #   and returns a custom prefix depending on the value

    $cloudType = (Get-AzContext).Environment.Name

    $prefix = switch -exact ($cloudType)
                {
                    "AzureCloud" {"AZCP"}
                    "AzureUSGovernment" {"AZGP"}
                    default {"AZNA"}
                }

    return $prefix
}

function GetSuffix
{
    #Use this function to provide the Suffix for your Az DevOps Service Connections
    #
    #The example shown here gets a tag named "subscriptionType" for the current Azure Subscription 
    #   and returns a custom suffix depending on the value 
    
    $subTypeTag = Get-AzTag -Name "subscriptionType"
    $subType = $subTypeTag.Values.Name

    $suffix = switch -exact ($subType)
                {
                    "Production" {"10"}
                    "NonProduction" {"70"}
                    default {"70"}
                }

    return $suffix
}

$tenantId = (Get-AzContext).Tenant.Id

#Create new SPN if doesnt exist

$AppRegName = "$azDevOpsOrgName-$azDevOpsProjName-spn"
$spn = Get-AzADServicePrincipal | Where-Object {$_.DisplayName -eq $AppRegName}

if(!$spn)
{
    # Create New SPN and Store Secret in Key Vault 
    
    Write-Host "Creating New SPN: $AppRegName for onboarding new project to Azure DevOps" -ForegroundColor Cyan
    $sp = New-AzADServicePrincipal -DisplayName $AppRegName -SkipAssignment -ErrorAction SilentlyContinue

    $appId = $sp.ApplicationId.Guid
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp.Secret)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    $secPassword = $password | ConvertTo-SecureString -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $AppRegName -SecretValue $secPassword
}
else 
{
    # Retrieve SPN Secret From Key Vault

    Write-Host "SPN: $AppRegName already exists" -ForegroundColor Green
    $appId = $spn.ApplicationId
    $AppRegPWSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $AppRegName -ErrorAction SilentlyContinue 

    if(!$AppRegPWSecret)
    {
        Write-Error "Key Vault Secret: $AppRegName with SPN Password does not exist.  Please create secret in KV or delete existing SPN: $AppRegName and try again." -ErrorAction Stop
    }

    $password = $AppRegPWSecret.SecretValueText
}

# Loop through each Azure Subscription
# ForEach Subscription: 
#   1) Create New Resource Group if it doesn't exist
#   2) Add new SPN as Contributor to Resource Group

foreach($SubscriptionID in $SubscriptionIDList)
{
    Select-AzSubscription -SubscriptionId $SubscriptionID | Out-Null

    $RG = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -eq $RGName}
    
    if(!$RG)
    {
        Write-Host "Creating New Resource Group: $RGName in Subscription: $SubscriptionId" -ForegroundColor Cyan
        New-AzResourceGroup -Location $RGLocation -Name $RGName
    }
    else 
    {        
        Write-Host "Resource Group: $RGName already exists in Subscription: $SubscriptionId" -ForegroundColor Green
    }

    $roleExists = Get-AzRoleAssignment -ResourceGroupName $RGName | Where-Object {($_.DisplayName -eq $AppRegName) -and ($_.RoleDefinitionName -eq "Contributor")}

    if(!$roleExists)
    {
        Write-Host "Adding Spn: $AppRegName to Contributor Role for: $RGName in Subscription: $SubscriptionId" -ForegroundColor Cyan
        New-AzRoleAssignment -ResourceGroupName $RGName -ApplicationId $appId -RoleDefinitionName Contributor
    }
    else
    {
        Write-Host "Spn: $AppRegName already Contributor for: $RGName in Subscription: $SubscriptionId" -ForegroundColor Green
    }
    
}

#Create Azure DevOps Service Connections

# Setup Environment for az cli/az devops
$Env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $password

$azDevOpsOrgUrl = "https://dev.azure.com/$azDevOpsOrgName/"

# Get Az DevOps PAT Secret Name from Key Vault and store as Env Variable

$AzDevOpsPATSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $azDevOpsPATSecretName -ErrorAction SilentlyContinue

if(!$AzDevOpsPATSecret)
{
    Write-Error "Key Vault Secret: $AzDevOpsPATSecret with Azure DevOps PAT does not exist.  Please create secret in KV and try again." -ErrorAction Stop
}

$azDevOpsPAT = $AzDevOpsPATSecret.SecretValueText

$env:AZURE_DEVOPS_EXT_PAT = $azDevOpsPAT

# Create new Az DevOps project if it doesnt exist

$projList = (az devops project list --org $azDevOpsOrgUrl | ConvertFrom-Json).value

$projExists = $projList | where-object {$_.name -eq $azDevOpsProjName}

if(!$projExists)
{
    Write-Host "Creating New Project: $azDevOpsProjName in DevOps Organization: $azDevOpsOrgName" -ForegroundColor Cyan
    az devops project create --organization $azDevOpsOrgUrl --name $azDevOpsProjName --description "Azure DevOps project created by Automated Process" 
}
else 
{
    Write-Host "Project: $azDevOpsProjName already exists in DevOps Organization: $azDevOpsOrgName" -ForegroundColor Green
}

# Loop through each Azure Subscription
# ForEach Subscription: Create New Service Connection if it doesnt exist

foreach($SubscriptionID in $SubscriptionIDList)
{
    Select-AzSubscription -SubscriptionId $SubscriptionID | Out-Null
    $SubscriptionName = (Get-AzSubscription | Where-Object {$_.SubscriptionId -eq "$SubscriptionID"}).Name
    
    $Prefix = GetPrefix
    $Suffix = GetSuffix

    $azDevOpsServiceConnName = "$Prefix-$azDevOpsProjName-$Suffix"

    $ServConnExists = az devops service-endpoint list --org $azDevOpsOrgUrl --project $azDevOpsProjName --query "[?name=='$azDevOpsServiceConnName']" | ConvertFrom-Json

    if(!$ServConnExists)
    {
        Write-Host "Creating New Service Connection: $azDevOpsServiceConnName in Project: $azDevOpsProjName" -ForegroundColor Cyan

        az devops service-endpoint azurerm create --azure-rm-service-principal-id $appId `
                                                  --azure-rm-subscription-id $SubscriptionID `
                                                  --azure-rm-subscription-name $SubscriptionName `
                                                  --azure-rm-tenant-id $tenantId `
                                                  --name $azDevOpsServiceConnName `
                                                  --organization $azDevOpsOrgUrl `
                                                  --project $azDevOpsProjName
    }
    else 
    {
        Write-Host "Service Connection: $azDevOpsServiceConnName already exists in Project: $azDevOpsProjName" -ForegroundColor Green    
    }

}

#Clear out Env Variables

$Env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $null
$env:AZURE_DEVOPS_EXT_PAT = $null