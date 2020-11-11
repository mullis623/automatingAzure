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
        $MainSiteARs
    )
    
    if($MainSiteARs.RuleName -eq "Allow all")
    {
        $priority = 100
    }
    else {
        $AllowRules = $MainSiteARs | Where-Object {$_.Action -eq "Allow"}
        $LastAllowPriority = ($AllowRules.Priority | Select-Object -Unique | Sort-Object)[-1]

        $priority = $LastAllowPriority + 1
    }

    return $priority
}

$FrontDoorIPRulesName = "FrontDoorBEServiceTagIPRule"
$BasicInfraIPRuleName = "AzureBasicInfraIPRule"
$FrontDoorIPRuleDescription = "Front Door Service Tag Allow"
$BasicInfraIPRuleDescription = "Azure Basic Infra IP Allow"
$AzBasicInfraIPs = @("168.63.129.16/32","169.254.169.254/32")
$ServiceTags = Get-AzNetworkServiceTag -location $location
$FrontDoorBackendIPList = ($ServiceTags.values | where-Object {$_.name -eq "AzureFrontDoor.Backend"}).properties.addressPrefixes

try 
{

    $MainSiteAccessRestrictions = (Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $TargetAppServiceRG -Name $TargetAppServiceName).MainSiteAccessRestrictions

    $FrontDoorACLRules = $MainSiteAccessRestrictions | Where-Object {$_.RuleName -eq $FrontDoorIPRulesName}
    $FrontDoorACLRuleIPs = $FrontDoorACLRules.IPAddress

    $FrontDoorPriority = $FrontDoorACLRules.Priority | Select-Object -Unique
    
    if(!$FrontDoorPriority){
        $FrontDoorPriority = Get-StartingAppServicePriority $MainSiteAccessRestrictions
    }

    $BasicInfraACLRules = $MainSiteAccessRestrictions | Where-Object {$_.RuleName -eq $BasicInfraIPRuleName}
    $BasicInfraACLRuleIPs = $BasicInfraACLRules.IPAddress

    $BasicInfraPriority = ($MainSiteAccessRestrictions | `
                            Where-Object {$_.RuleName -eq $BasicInfraIPRuleName}).Priority | `
                            Select-Object -Unique

    if(!$BasicInfraPriority)
    {
        $BasicInfraPriority = $FrontDoorPriority + 1
    }

    $FrontDoorACLRuleIPs = $FrontDoorACLRuleIPs | Sort-Object
    $FrontDoorBackendIPList = $FrontDoorBackendIPList | Sort-Object
    $BasicInfraACLRuleIPs = $BasicInfraACLRuleIPs | Sort-Object
    $AzBasicInfraIPs = $AzBasicInfraIPs | Sort-Object 

    $FDIPCompare = Compare-Object $FrontDoorACLRuleIPs $FrontDoorBackendIPList 

    $FDIPsToAdd = $FDIPCompare | where-object {$_.SideIndicator -eq "=>"} | Select-Object -ExpandProperty InputObject
    $FDIPsToRemove = $FDIPCompare | where-object {$_.SideIndicator -eq "<="} | Select-Object -ExpandProperty InputObject

    $BasicInfraIPCompare = Compare-Object $BasicInfraACLRuleIPs $AzBasicInfraIPs

    $BasicInfraIPsToAdd = $BasicInfraIPCompare | where-object {$_.SideIndicator -eq "=>"} | Select-Object -ExpandProperty InputObject
    $BasicInfraIPsToRemove = $BasicInfraIPCompare | where-object {$_.SideIndicator -eq "<="} | Select-Object -ExpandProperty InputObject
    
    #Add New Front Door Backend IPs to App Service ACL
    foreach($FDIPToAdd in $FDIPsToAdd)
    {
        Write-Host "Adding new Allow Rule for IP: $FDIPToAdd to App Service: $TargetAppServiceName" -ForegroundColor Green
        Add-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG `
                                          -WebAppName $TargetAppServiceName `
                                          -Name $FrontDoorIPRulesName `
                                          -Priority $FrontDoorPriority `
                                          -Action "Allow" `
                                          -Description $FrontDoorIPRuleDescription `
                                          -IpAddress $FDIPToAdd | Out-Null
        
    }

    #Remove Front Door Backend IPs that are no longer in the Service Tag IP List
    foreach($FDIPToRemove in $FDIPsToRemove)
    {
        Write-Host "Removing Allow Rule for IP: $FDIPToRemove to App Service: $TargetAppServiceName since it no longer exists in Service Tag IP List" -ForegroundColor Yellow
        Remove-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG `
                                             -WebAppName $TargetAppServiceName `
                                             -Action "Allow" `
                                             -IpAddress $FDIPToRemove | Out-Null
        
    }

    #Add New Azure Basic Infra IPs to App Service ACL
    foreach($BasicInfraIPToAdd in $BasicInfraIPsToAdd)
    {
        Write-Host "Adding new Allow Rule for IP: $BasicInfraIPToAdd to App Service: $TargetAppServiceName" -ForegroundColor Green
        Add-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG `
                                          -WebAppName $TargetAppServiceName `
                                          -Name $BasicInfraIPRuleName `
                                          -Priority $BasicInfraPriority `
                                          -Action "Allow" `
                                          -Description $BasicInfraIPRuleDescription `
                                          -IpAddress $BasicInfraIPToAdd | Out-Null
        
    }

    #Remove Azure Basic Infra IPs that are no longer in use
    foreach($BasicInfraIPToRemove in $BasicInfraIPsToRemove)
    {
        Write-Host "Removing Allow Rule for IP: $BasicInfraIPToRemove to App Service: $TargetAppServiceName since it is no longer used with Azure Basic Infrastructure" -ForegroundColor Yellow
        Remove-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG `
                                             -WebAppName $TargetAppServiceName `
                                             -Action "Allow" `
                                             -IpAddress $BasicInfraIPToRemove | Out-Null
        
    }

}
catch {
    Write-Error $Error[0]
    exit 1
}
