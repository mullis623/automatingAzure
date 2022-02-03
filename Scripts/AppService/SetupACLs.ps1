<#  This script will add an Access Control list to a target App Service and/or Firewall Rules for a SQL Server 
    for the outbound IP Addresses used by a Source App Service.  

    For the source App Service there are 2 possibilities for Outbound IP Address to use in Firewall Rules and ACLs. 
        1) OutboundIPAddresses - current Outbound IP Addresses in use by the App Service based on Region, Resource Group, and SKU
        2) PossibleOutboundIPAddresses - all possible Outbound IP Addresses that could be used by this App Service.  This list will include
        all IPs in 1) plus any others that could be used after a scale up or scale down operation where a change in the performance tier results
        (Standard to Premium or Vice Versa)

        If you only want to add the IPs in 1) to the ACLs/Firewall Rules, do not use the -AllPossibleOutboundIPs switch.  That switch is only used
        when you want to add all IPs as described in 2) to the ACLs/Firewall Rules.

    Usage:

        If all Resources (Source and Target App Services and SQL Server) are in the same Resource Group, the -RGName parameter can be used. 
        Otherwise, each Resource Group Name needs to be specified along with the resource name.  

        Example 1 (All Resources in the same Resource Group with both App Service and SQL Server as Targets using All Possible Outbound IPs)

        .\SetupACLs.ps1 -SourceAppServiceName "SrcName" -TargetAppServiceName "TarName" -RGName "ResourceGroup" -SQLServerName "SQLName" -AllPossibleOutboundIPs

        Example 2 (All Resources in the same Resource Group with both App Service and SQL Server as Targets)

        .\SetupACLs.ps1 -SourceAppServiceName "SrcName" -TargetAppServiceName "TarName" -RGName "ResourceGroup" -SQLServerName "SQLName"

        Example 3 (Resources in different Resource Groups with both App Service and SQL Server as Targets)

        .\SetupACLs.ps1 -SourceAppServiceName "SrcName" -SourceAppServiceRG "SrcRGName" -TargetAppServiceName "TarName" -TargetAppServiceRG "TarRGName" -SQLServerName "SQLName" -SQLServerRG "SQLRG"

        Example 4 (Resources in different Resource Groups with only App Service as Target)

        .\SetupACLs.ps1 -SourceAppServiceName "SrcName" -SourceAppServiceRG "SrcRGName" -TargetAppServiceName "TarName" -TargetAppServiceRG "TarRGName"

        Example 5 (Resources in different Resource Groups with only SQL Server as Target)

        .\SetupACLs.ps1 -SourceAppServiceName "SrcName" -SourceAppServiceRG "SrcRGName" -SQLServerName "SQLName" -SQLServerRG "SQLRG"

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$SourceAppServiceName,
    [string]$TargetAppServiceName,
    [string]$SQLServerName,
    [Parameter(Mandatory=$true,
        ParameterSetName = 'SameRG')]
    [string]$RGName,
    [Parameter(Mandatory=$true,
        ParameterSetName = 'SeparateRGs')]
    [string]$SourceAppServiceRG,
    [Parameter(Mandatory=$false,
        ParameterSetName = 'SeparateRGs')]
    [string]$TargetAppServiceRG,
    [Parameter(Mandatory=$false,
        ParameterSetName = 'SeparateRGs')]
    [string]$SQLServerRG,    
    [switch]$AllPossibleOutboundIPs
)

#Input Validation

if(!($TargetAppServiceName -or $SQLServerName))
{
    Write-Error "Target App Service or Target SQL Server required for adding Access Control Lists/Firewall Rules"
    exit 1
}

if($RGName)
{
    $SourceAppServiceRG = $RGName
    $TargetAppServiceRG = $RGName
    $SQLServerRG = $RGName
}

if($TargetAppServiceName)
{
    if(!$TargetAppServiceRG)
    {
        Write-Error "TargetAppServiceRG parameter required with App Service as Target"
        exit 1
    }
    
}

if($SQLServerName)
{
    if(!$SQLServerRG)
    {
        Write-Error "SQLServerRG parameter required with SQL Server as Target"
        exit 1
    }
    
}

# Function to determine Priority for App Service ACL Rules
# This will get the highest priority from the current allow rules and add 1 to it or 100 if no rules are currently defined.  
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

# Get Outbound IPs from Source App Service

try{
    $SourceApp = Get-AzWebApp -ResourceGroupName $SourceAppServiceRG -Name $SourceAppServiceName

    if($AllPossibleOutboundIPs)
    {
        $SourceIPString = $SourceApp.PossibleOutboundIpAddresses
    }
    else {
        $SourceIPString = $SourceApp.OutboundIpAddresses
    }

    $SourceIPList = $SourceIPString.Split(",")
}
catch{
    Write-Error "An error occurred getting App Service details for App Service: $SourceAppServiceName in Resource Group: $SourceAppServiceRG.
    Please Ensure that Source App Service Name and Resource Group were entered correctly"

    exit 1
}

#Get current details for ACL on Target App Service and Initialize Loop Variables
if($TargetAppServiceName)
{
    $AccessRestrictionConfig = Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $TargetAppServiceRG -Name $TargetAppServiceName
    $WebAppPriority = Get-StartingAppServicePriority $AccessRestrictionConfig
    $WebAppRuleIPs = $AccessRestrictionConfig.MainSiteAccessRestrictions.IpAddress
    $WebAppRuleNames = $AccessRestrictionConfig.MainSiteAccessRestrictions.RuleName
    $WebAppCount = 1
}

#Get current Firewall Rules on Target SQL Server and Initialize Loop Variables
if($SQLServerName)
{
    $FirewallRules = Get-AzSqlServerFirewallRule -ServerName $SQLServerName -ResourceGroupName $SQLServerRG
    $SQLRuleIPs = $FirewallRules.StartIpAddress
    $SQLRuleNames = $FirewallRules.FirewallRuleName
    $SQLCount = 1
}

<#  Loop to add an rule to the Target App Service ACL and/or a Firewall rule to SQL Server
    Rules will only be added if the IP does not currently exist in any other rule.  
    To ensure unique rule names, a count is used that will increment if the same rule name already exists.  #>

foreach($SourceIP in $SourceIPList)
{

    if($TargetAppServiceName)
    {    
        $IPtoAdd = "$SourceIP/32"

        if($IPtoAdd -notin $WebAppRuleIPs)
        {
            $ACLRuleName = "$SourceAppServiceName-Rule$WebAppCount"
            while($ACLRuleName -in $WebAppRuleNames)
            {
                $WebAppCount++
                $ACLRuleName = "$SourceAppServiceName-Rule$WebAppCount"
            }
            Write-Host "Adding new Allow Rule for IP: $IPtoAdd to App Service: $TargetAppServiceName" -ForegroundColor Green
            Add-AzWebAppAccessRestrictionRule -ResourceGroupName $TargetAppServiceRG -WebAppName $TargetAppServiceName -Name $ACLRuleName -Priority $WebAppPriority -Action Allow -IpAddress $IPtoAdd | Out-Null
            $WebAppCount++
        }
    }

    if($SQLServerName)
    {
        if($SourceIP -notin $SQLRuleIPs)
        {
            $FirewallRuleName = "$SourceAppServiceName-Rule$SQLCount"
            while($FirewallRuleName -in $SQLRuleNames)
            {
                $SQLCount++
                $FirewallRuleName = "$SourceAppServiceName-Rule$SQLCount"
            }
            Write-Host "Adding new Allow Rule for IP: $IPtoAdd to SQL Server: $SQLServerName" -ForegroundColor Green
            New-AzSqlServerFirewallRule -FirewallRuleName $FirewallRuleName -StartIpAddress $SourceIP -EndIpAddress $SourceIP -ServerName $SQLServerName -ResourceGroupName $SQLServerRG | Out-Null
            $SQLCount++
        }
    }

}