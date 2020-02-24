[CmdletBinding()]
param (
    [string]$CSVFileName,
    [string]$ScriptPath #Added for use in Azure DevOps PowerShell Task
)

$WorkingDirectory = Get-Location

if(!$ScriptPath)
{
    $ScriptPath = $WorkingDirectory
}

$ResourceGroups = (Get-AzResourceGroup).ResourceGroupName
$csv = Import-Csv "$ScriptPath\$CSVFileName"

Write-Host "ScriptPath: $ScriptPath"

foreach($Tags in $csv)
{
    $ResourceGroup = $Tags.ResourceGroupName
    $ResourceTags = $null

    if($ResourceGroup -in $ResourceGroups)
    {       
        Write-Host "Resource Group: $ResourceGroup found in current Subscription" -ForegroundColor Green
        $ResourceTags = $Tags.PSObject.Properties | Foreach-Object {
            [PSCustomObject]@{
                TagName = $_.Name
                TagValue = $_.Value
            }
        }
        
        $CurrentTags = (Get-AzResourceGroup -Name $ResourceGroup).Tags
        $NewTags = $null

        foreach($ResourceTag in $ResourceTags)
        {
            $NewTag = $null
            $TagName = $ResourceTag.TagName
            $TagValue = $ResourceTag.TagValue

            
            if(!$CurrentTags)
            {
                $CurrentTags = @{}
            }    
            
            if($CurrentTags.ContainsKey($TagName))
            {
                $CurrentValue = $CurrentTags[$TagName]
                if($CurrentValue -ne $TagValue)
                {
                    Write-Host "Updating Tag: $TagName on ResourceGroup: $ResourceGroup" -ForegroundColor Cyan
                    $NewTag = @{$TagName=$TagValue}
                    $CurrentTags.Remove($TagName)
                }
                else {
                    Write-Host "Tag: $TagName already exists with the correct value on Resource Group: $ResourceGroup" -ForegroundColor Green
                }
            }
            elseif (!$TagValue) 
            {
                Write-Host "Skipping since Tag: $TagName does not have a value for RG: $ResourceGroup." -ForegroundColor Yellow    
            }
            else {
                Write-Host "Adding Tag: $TagName to ResourceGroup: $ResourceGroup" -ForegroundColor Cyan
                $NewTag = @{$TagName=$TagValue}
            }

            if($NewTag)
            {
                $NewTags += $NewTag
            }
            
        }

        if($NewTags)
        {
            Write-Host "Writing New Tags to Resource Group: $ResourceGroup" -ForegroundColor Cyan
            $CurrentTags += $NewTags
            Set-AzResourceGroup -Name $ResourceGroup -Tag $CurrentTags
        }
        else {
            Write-Host "Tags already up to date for Resource Group: $ResourceGroup" -ForegroundColor Green
        }
        
    }
    else {
        Write-Host "Skipping Resource Group: $ResourceGroup since it is not found in current Subscription" -ForegroundColor Yellow 
    }
}