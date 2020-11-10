[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$TargetAppServiceName,
    [Parameter(Mandatory=$true)]
    [string]$TargetAppServiceRG,
    [string]$location = "eastus2"
)

function Get-StartingAppServicePriority
{
    [CmdletBinding()]
    param (
        $ARConfig
    )
    
    if($ARConfig.MainSiteAccessRestrictions.RuleName -eq "Allow all")
    {
        $priority = 100
    }
    else {
        $AllowRules = $ARConfig.MainSiteAccessRestrictions | Where-Object {$_.Action -eq "Allow"}
        $LastAllowPriority = ($AllowRules.Priority | Select-Object -Unique | Sort-Object)[-1]

        $priority = $LastAllowPriority + 1
    }

    return $priority
}

$ServiceTags = Get-AzNetworkServiceTag -location $location
$FrontDoorBackendIPList = ($ServiceTags.values | where-Object {$_.name -eq "AzureFrontDoor.Backend"}).properties.addressPrefixes

try 
{

    $AccessRestrictionConfig = Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $TargetAppServiceRG -Name $TargetAppServiceName
    $FrontDoorPriority = ($AccessRestrictionConfig.MainSiteAccessRestrictions | `
                            Where-Object {$_.RuleName -eq "FrontDoorBEServiceTagIPRule"}).Priority | `
                            Select-Object -Unique
    
    if(!$FrontDoorPriority){
        $FrontDoorPriority = Get-StartingAppServicePriority $AccessRestrictionConfig
    }

    $BasicInfraPriority = ($AccessRestrictionConfig.MainSiteAccessRestrictions | `
                            Where-Object {$_.RuleName -eq "AzureBasicInfraIPRule"}).Priority | `
                            Select-Object -Unique

    if(!$BasicInfraPriority)
    {
        $BasicInfraPriority = $FrontDoorPriority + 1
    }
    
    $WebAppRuleIPs = $AccessRestrictionConfig.MainSiteAccessRestrictions.IpAddress
    
    foreach($FrontDoorBackendIP in $FrontDoorBackendIPList)
    {
        if($FrontDoorBackendIP -notin $WebAppRuleIPs)
        {
            #$ACLRuleName = "FrontDoorBEServiceTagIPRule"

            #Write-Host "Name: $($ACLRuleName.Length)"

            Write-Host "Adding new Allow Rule for IP: $FrontDoorBackendIP to App Service: $TargetAppServiceName" -ForegroundColor Green
            Add-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG `
                                              -WebAppName $TargetAppServiceName `
                                              -Name "FrontDoorBEServiceTagIPRule" `
                                              -Priority $FrontDoorPriority `
                                              -Action "Allow" `
                                              -Description "Front Door Service Tag Allow" `
                                              -IpAddress $FrontDoorBackendIP | Out-Null
        }
    }
    
    $AzBasicInfraIPs = "168.63.129.16/32","169.254.169.254/32"
    foreach($AzBasicInfraIP in $AzBasicInfraIPs)
    {
        if($AzBasicInfraIP -notin $WebAppRuleIPs)
        {
            Write-Host "Adding new Allow Rule for IP: $AzBasicInfraIP to App Service: $TargetAppServiceName" -ForegroundColor Green
            Add-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG `
                                              -WebAppName $TargetAppServiceName `
                                              -Name "AzureBasicInfraIPRule" `
                                              -Priority $BasicInfraPriority `
                                              -Action "Allow" `
                                              -Description "Azure Basic Infra IP Allow" `
                                              -IpAddress $AzBasicInfraIP | Out-Null
        }

    }

}
catch {
    Write-Error $Error[0]
    exit 1
}
