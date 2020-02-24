[CmdletBinding()]
param (
    [string]$CSVFileName = "RGTagExport.csv",
    [string]$ScriptPath #Added for use in Azure DevOps PowerShell Task
)

$Global:TagNameList = @()

function AddKeysToTagNameList
{
    [CmdletBinding()]
    param (
        [Hashtable]$Tags
    )

    $Tags.Keys | foreach-Object {
        if(!($_ -in $Global:TagNameList))
        {
            $Global:TagNameList += $_
        }        
    }
}

$WorkingDirectory = Get-Location

if(!$ScriptPath)
{
    $ScriptPath = $WorkingDirectory
}

$ResourceGroups = (Get-AzResourceGroup).ResourceGroupName
#$ResourceGroups = "AKS_DEMO", "DataFactory"
$csvFile = "$ScriptPath\$CSVFileName"
$RGsWithTags = @()

if(Test-Path $csvFile)
{
    Remove-Item $csvFile
}

New-Item $csvFile

Write-Host "ScriptPath: $ScriptPath"

foreach($ResourceGroup in $ResourceGroups)
{
    Write-Output "Compiling Tag Keys for Resource Group: $ResourceGroup..."
    
    $RGTags = $null
    
    $RGTags = (Get-AzResourceGroup -Name $ResourceGroup).Tags
    
    if($RGTags.Count -gt 0)
    {
        AddKeysToTagNameList $RGTags | Out-Null
        $RGsWithTags += $ResourceGroup
    }    
            
}

if($Global:TagNameList.Count -gt 0)
{
    $TagNameCSVString = ""

    foreach($TagName in $Global:TagNameList)
    {
        $TagNameCSVString += "$TagName, "
    }

    $TagNameCSVString = $TagNameCSVString.TrimEnd(', ')

    $TagNameCSVString | Out-File $csvFile -Append
}

foreach($RG in $RGsWithTags)
{
    Write-Output "Writing Tags out to CSV File for Resource Group: $RG"
    
    $RGTags = $null
    $TagValueCSVString = ""
    
    $RGTags = (Get-AzResourceGroup -Name $RG).Tags
    
    foreach($TagName in $Global:TagNameList)
    {   
        $TagValue = $RGTags.Item($TagName)
     
        if($TagName -eq "ResourceGroupName")
        {
            if(!$TagValue)
            {
                Write-Output "      Adding Tag for ResourceGroupName since it does not exist."
                $TagValue = $RG
            }
        }

        $TagValueCSVString += "$TagValue, "
    }

    $TagValueCSVString = $TagValueCSVString.TrimEnd(', ')
    $TagValueCSVString | Out-File $csvFile -Append
            
}