param
(
    [string]$AppRegName,
    [string]$keyVaultName,
    [string]$appRegPasswordSecretName,
    [string]$azDevOpsPATSecretName,
    [array]$SubscriptionIDList,
    [string]$RGName,
    [string]$RGLocation,
    [string]$azDevOpsOrgName,
    [string]$azDevOpsProjName
)

function GetSubIdFromScope
{
    [CmdletBinding()]
    param 
    (
        [string]$Scope
    )

    $startingIndex = "/subscriptions/".Length
    $subId = $scope.Substring($startingIndex,($scope.IndexOf("/resourceGroups")-$startingIndex))

    return $subId
}

function GetRGNameFromScope
{
    [CmdletBinding()]
    param 
    (
        [string]$Scope
    )

    $Name = $Scope.Substring($Scope.LastIndexOf("/")+1)

    return $Name
}

function GetSubType
{
    param 
    (
        [string]$subscriptionId
    )

    $subTypeTag = az tag list --subscription $subscriptionId --query "[?tagName=='subscriptionType']" | ConvertFrom-Json
    $subType = $subTypeTag.value.TagValue

    return $subType

}

function GetSuffix
{
    param 
    (
        [string]$subType
    )

    $suffix = switch -exact ($subType)
                {
                    "Production" {"10"}
                    "NonProduction" {"70"}
                    default {"00"}
                }

    return $suffix
}

function GetCloudType
{
    param 
    (
        [string]$subscriptionId
    )

    $sub = az account list --query "[?id=='$subscriptionId']" | ConvertFrom-Json
    $cloudType = $sub.cloudName

    return $cloudType
}

function GetPrefix
{
    param 
    (
        [string]$cloudType
    )

    $prefix = switch -exact ($cloudType)
                {
                    "AzureCloud" {"AZCP"}
                    "AzureUSGovernment" {"AZGP"}
                    default {"AZNA"}
                }

    return $prefix
}

#Create new SPN if doesnt exist

$spObjId = az ad sp list --display-name $AppRegName --query [].objectId --output tsv

if(!$spObjId)
{
    Write-Host "Creating New SPN: $AppRegName for onboarding new project to Azure DevOps" -ForegroundColor Cyan
    $Result = az ad sp create-for-rbac -n $AppRegName --skip-assignment | ConvertFrom-Json

    $appId = $Result.appId
    $password = $Result.password
    $tenantId = $Result.tenant
    $spObjId = az ad sp list --display-name $AppRegName --query [].objectId --output tsv
    az keyvault secret set --name $appRegPasswordSecretName --vault-name $keyVaultName --value $password
}
else 
{
    Write-Host "SPN: $AppRegName already exists" -ForegroundColor Green
    $spn = az ad sp show --id $spObjId | ConvertFrom-Json
    $appId = $spn.appId
    $tenantId = $spn.appOwnerTenantId
    $AppRegPWSecret = az keyvault secret show --name $appRegPasswordSecretName --vault-name $keyVaultName | ConvertFrom-Json
    $password = $AppRegPWSecret.value
}

foreach($SubscriptionID in $SubscriptionIDList)
{
    $RGScope = "/subscriptions/$SubscriptionID/resourceGroups/$RGName"

    az account set --subscription $SubscriptionId

    $RG = az group list --query "[?name=='$RGName']" | ConvertFrom-Json
    
    if(!$RG)
    {
        Write-Host "Creating New Resource Group: $RGName in Subscription: $SubscriptionId" -ForegroundColor Cyan
        az group create --location $RGLocation --name $RGName
    }
    else 
    {        
        Write-Host "Resource Group: $RGName already exists in Subscription: $SubscriptionId" -ForegroundColor Green
    }

    $roleExists = az role assignment list --resource-group $RGName --query "[?principalId=='$spObjId']" | ConvertFrom-Json

    if(!$roleExists)
    {
        Write-Host "Adding Spn: $AppRegName to Contributor Role for: $RGName in Subscription: $SubscriptionId" -ForegroundColor Cyan
        az role assignment create --role "Contributor" --assignee-object-id $spObjId --scope $RGScope
    }
    else
    {
        Write-Host "Spn: $AppRegName already Contributor for: $RGName in Subscription: $SubscriptionId" -ForegroundColor Green
    }
    
}

#Create Azure DevOps Service Connections

$Env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $password

$AzDevOpsPATSecret = az keyvault secret show --name $azDevOpdPATSecretName --vault-name $keyVaultName | ConvertFrom-Json
$azDevOpsPAT = $AzDevOpsPATSecret.value

$env:AZURE_DEVOPS_EXT_PAT = $azDevOpsPAT

$env:AZURE_DEVOPS_EXT_PAT | az devops login --organization $azDevOpsOrgName

$projList = (az devops project list | ConvertFrom-Json).value

$projExists = $projList | where-object {$_.name -eq $azDevOpsProjName}

if(!$projExists)
{
    Write-Host "Creating New Project: $azDevOpsProjName in DevOps Organization: $azDevOpsOrgName" -ForegroundColor Cyan
    az devops project create  --organization $azDevOpsOrgName --name $azDevOpsProjName --description "Azure DevOps project for Application: $AppRegName" 
}
else 
{
    Write-Host "Project: $azDevOpsProjName already exists in DevOps Organization: $azDevOpsOrgName" -ForegroundColor Green
}

foreach($SubscriptionID in $SubscriptionIDList)
{
    $SubscriptionName = (az account list --query "[?id=='$SubscriptionID']" | ConvertFrom-Json).name
    
    $cType = GetCloudType -subscriptionId $SubscriptionID
    $Prefix = GetPrefix -cloudType $cType
    $sType = GetSubType -subscriptionId $SubscriptionID
    $Suffix = GetSuffix -subType $sType

    $azDevOpsServiceConnName = "$Prefix-$azDevOpsProjName-$Suffix"

    $ServConnExists = az devops service-endpoint list --project $azDevOpsProjName --query "[?name=='$azDevOpsServiceConnName']" | ConvertFrom-Json

    if(!$ServConnExists)
    {
        Write-Host "Creating New Service Connection: $azDevOpsServiceConnName in Project: $azDevOpsProjName" -ForegroundColor Cyan

        az devops service-endpoint azurerm create --azure-rm-service-principal-id $appId `
                                                  --azure-rm-subscription-id $SubscriptionID `
                                                  --azure-rm-subscription-name $SubscriptionName `
                                                  --azure-rm-tenant-id $tenantId `
                                                  --name $azDevOpsServiceConnName `
                                                  --organization $azDevOpsOrgName `
                                                  --project $azDevOpsProjName
    }
    else 
    {
        Write-Host "Service Connection: $azDevOpsServiceConnName already exists in Project: $azDevOpsProjName" -ForegroundColor Green    
    }

    
}

$Env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $null
$env:AZURE_DEVOPS_EXT_PAT = $null