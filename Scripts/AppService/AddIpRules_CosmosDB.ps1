<#  This script will add an IP Rules to an Azure CosmosDB Account with Source IPs coming from App Service, Azure Synapse, and Azure Portal  

    Note: This script is designed to update the IP Rules in a CosmosDB Account using the following process:
        1) Get Current IP Rules in Cosmos DB Account to ensure IPs are only added to the IP Rules list if they do not yet exist 
        (This script can only be used to add IPs to the current list and will not remove any stale IPs or IP ranges. The firewall list sbould be evauluated periodically 
        and any stale entries should be removed manually)
        2) Adds the required IP Rules to enable access to the Cosmos DB Account from the Azure Portal if the required switch is included they do not yet exist
        3) Adds the App Service/Function Outbound IPs to the Cosmos DB IP Rules (see section below for detailed explantion around which IPs will be included)
        3) If defined, the IP Ranges to allow Azure Synapse to connect to CosmosBB are also added to the IP Rules list.  By default, Azure Synapse utilizes
        backend IPs available under the SQL Service Tag when creating the Backend Pools (Sql Pools, Appche Spark Pools, etc.) The IPs that are added to the CosmosDB IP
        Rules list are all the available IPv4 ranges in the SQl Service Tag for the region where Synapse is deployed.   
        4) Once the full list of IP Rules has been generated through the above process, the CosmosDB Account is updated with the new list.  The IPs are not added one at a time
        as with some other services. 

    For the source App Service there are 2 possibilities for the Outbound IP Addresses to use in CosmosDB Account IP Rules. 
        1) OutboundIPAddresses - current Outbound IP Addresses in use by the App Service based on Region, Resource Group, and SKU
        2) PossibleOutboundIPAddresses - all possible Outbound IP Addresses that could be used by this App Service.  This list will include
        all IPs in 1) plus any others that could be used after a scale up or scale down operation where a change in the performance tier results
        (Standard to Premium or Vice Versa)

        If you only want to add the IPs in 1) to the ACLs/Firewall Rules, do not use the -AllPossibleOutboundIPs switch.  That switch is only used
        when you want to add all IPs as described in 2) to the ACLs/Firewall Rules.

    Usage:

        If all Resources (App Service, and CosmosDB Account, and Synapse Workspace) are in the same Resource Group, the -RGName parameter can be used. 
        Otherwise, each Resource Group Name needs to be specified along with the resource name.  

        Example 1 (All Resources in the same Resource Group with Source IPs from App Service using All Possible Outbound IPs, Azure Synapse, and Azure Portal. 
        Portal Access IPs and Synapse IPs also included)

        .\AddIpRules_CosmosDB.ps1 -AppServiceName "AppName" -CosmosDBName "CosmosAccountName" -RGName "ResourceGroup" -AllPossibleOutboundIPs -EnablePortalAccessForCosmos -SynapseName "SynapseName"

        Example 2 (All Resources in the same Resource Group with Source IPs from App Service using All Possible Outbound IPs)

        .\AddIpRules_CosmosDB.ps1 -AppServiceName "AppName" -CosmosDBName "CosmosAccountName" -RGName "ResourceGroup" -AllPossibleOutboundIPs

        Example 3 (Resources in different Resource Groups with Source IPs from App Service - just current Outbound IPs)

        .\AddIpRules_CosmosDB.ps1 -AppServiceName "AppName" -AppServiceRG "AppServiceResourceGroup" -CosmosDBName "CosmosAccountName" -CosmosDBRG "CosmosResourceGroup" -SynapseName "SynapseName" -SynapseRGName "SynapseResourceGroup"

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$AppServiceName,
    [string]$CosmosDBName,
    [Parameter(Mandatory=$true,
        ParameterSetName = 'SameRG')]
    [string]$RGName,
    [Parameter(Mandatory=$true,
        ParameterSetName = 'SeparateRGs')]
    [string]$AppServiceRG,
    [Parameter(Mandatory=$false,
        ParameterSetName = 'SeparateRGs')]
    [string]$CosmosDBRG,
    [string]$SynapseName,
    [string]$SynapseRGName,    
    [switch]$AllPossibleOutboundIPs,
    [switch]$EnablePortalAccessForCosmos    
)

#Input Validation

if(!$CosmosDBName)
{
    Write-Error "CosmosDB Name required for adding Access Control Lists/Firewall Rules"
    exit 1
}

if($RGName)
{
    $AppServiceRG = $RGName
    $CosmosDBRG = $RGName
}

if($SynapseName)
{
    if(!$SynapseRGName)
    {
        if($RGName)
        {
            $SynapseRGName = $RGName
        }
        else {
            Write-Error "SynapseName provided without SynapseRGName.  Please provide a value for RGName or SynapseRGName and retry."
        }
        
    }
}

if(!$CosmosDBRG)
{
    Write-Error "CosmosDBRG parameter required when not in the same Resource Group as App Service."
    exit 1
}

#Get current Firewall Rules on Target Cosmos DB Account

$CosmosFirewallRules = @()
$CosmosIPRules = (Get-AzCosmosDBAccount -Name $CosmosDBName -ResourceGroupName $CosmosDBRG).IpRules
foreach($IpRule in $CosmosIpRules)
{
    $CosmosFirewallRules += $IpRule.IpAddressOrRangeProperty
}

$ExistingFirewallRules = $CosmosFirewallRules

if($EnablePortalAccessForCosmos)
{
    $PortalAccessIPList = @("104.42.195.92", "40.76.54.131", "52.176.6.30", "52.169.50.45", "52.187.184.26")

    foreach($ip in $PortalAccessIPList)
    {
        if($ip -notin $CosmosFirewallRules)
        {
            $CosmosFirewallRules += $ip
        }
    }
}

# Get Outbound IPs from Source App Service

try{
    $AppService = Get-AzWebApp -ResourceGroupName $AppServiceRG -Name $AppServiceName

    if($AllPossibleOutboundIPs)
    {
        $AppServiceIPString = $AppService.PossibleOutboundIpAddresses
    }
    else {
        $AppServiceIPString = $SourceApp.OutboundIpAddresses
    }

    $AppServiceIPList = $AppServiceIPString.Split(",")
}
catch{
    Write-Error "An error occurred getting App Service details for App Service: $AppServiceName in Resource Group: $AppServiceRG.
    Please Ensure that Source App Service Name and Resource Group were entered correctly"

    exit 1
}

<#  Loop to add App Service Outbound IPs to CosmosDB Firewall Rules
    Rules will only be added if the IP does not currently exist in any other rule.  
    To ensure unique rule names, a count is used that will increment if the same rule name already exists.  #>

foreach($AppServiceIP in $AppServiceIPList)
{
    if($AppServiceIP -notin $CosmosFirewallRules)
    {
        $CosmosFirewallRules += $AppServiceIP
    }   

}

if($SynapseName)
{
    $SynapseRegion = (Get-AzSynapseWorkspace -ResourceGroupName VALottery-RG -Name valottery-synapse).location

    if(!$SynapseRegion)
    {
        Write-Error "Synapse region not available.  Please ensure that that SynapseName SynapseRGName parameters were passed in correctly"

        exit 1
    }

    $ServiceTags = Get-AzNetworkServiceTag -Location $SynapseRegion

    $SynapseIPRanges = ($ServiceTags.Values | where-object{$_.Name -eq "Sql.$SynapseRegion"}).Properties.AddressPrefixes

    foreach($ip in $SynapseIPRanges)
    {
        if($ip -notin $CosmosFirewallRules)
        {
            if($ip -match '\b(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}\b')
            {
                $CosmosFirewallRules += $ip
            }            
        }
    }    
}

$ExistingFirewallRules = $ExistingFirewallRules | Sort-Object
$CosmosFirewallRules = $CosmosFirewallRules | Sort-Object

$NeedToUpdate = Compare-Object $ExistingFirewallRules $CosmosFirewallRules

if($NeedToUpdate)
{
    Write-Host "Number of IP Ranges to add to CosmosDB: $($NeedToUpdate.Count)"
    Write-Host "Total Number of IP Rules in CosmosDB: $($CosmosFirewallRules.Count)"
    #Write-Host $CosmosFirewallRules
    Update-AzCosmosDBAccount -ResourceGroupName $CosmosDBRG -Name $CosmosDBName -IpRule $CosmosFirewallRules
}

