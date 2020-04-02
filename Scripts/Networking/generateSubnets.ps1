[CmdletBinding()]
param (
    [string]$masterRange,
    [string]$subnetSize
)

function GetCurrentOctetStartingIP
{
    param
    (
        [int]$OctetNumber,
        [string]$IP
    )
    
    $Octets = $IP.Split(".")

    $Octet = switch -exact ($OctetNumber) {
        1 { $Octets[0] }
        2 { $Octets[1] }
        3 { $Octets[2] }
        4 { $Octets[3] }
        default { "NA" }
    }
    
    return $Octet
    
}

function GetCurrentOctetPrefix
{
    param
    (
        [int]$OctetNumber,
        [string]$IP
    )
    
    $Octets = $IP.Split(".")

    $Prefix = switch -exact ($OctetNumber) {
        1 { $null }
        2 { "$($Octets[0])" }
        3 { "$($Octets[0]).$($Octets[1])" }
        4 { "$($Octets[0]).$($Octets[1]).$($Octets[2])" }
        default { "NA" }
    }
    
    return $Prefix
    
}

function GetCurrentOctetSuffix
{
    param
    (
        [int]$OctetNumber,
        [string]$IP
    )
    
    $Octets = $IP.Split(".")

    $Suffix = switch -exact ($OctetNumber) {
        1 { "$($Octets[1]).$($Octets[2]).$($Octets[3])" }
        2 { "$($Octets[2]).$($Octets[3])" }
        3 { "$($Octets[3])" }
        4 { $null }
        default { "NA" }
    }
    
    return $Suffix
}

#$masterRange = "10.10.0.0/16"
#$subnetSize = "17"

$StartingIP = $MasterRange.Substring(0,$MasterRange.IndexOf("/"))
$masterSubnetSize =  $MasterRange.Substring($MasterRange.IndexOf("/")+1,($MasterRange.Length-($MasterRange.IndexOf("/")+1)))

$subnetAddFactor = switch -exact ($subnetSize) {
    24 { 1 }
    23 { 2 }
    22 { 4 }
    21 { 8 }
    20 { 16 }
    19 { 32 }
    18 { 64 }
    17 { 128 }
    16 { 256 }
    default { "NA" }
}

$numberOfSubnets = [math]::pow(2,($subnetSize-$masterSubnetSize))

if(($masterSubnetSize -gt 15) -and ($masterSubnetSize -lt 24))
{
    $CurrentOctet = 3
    $LastOctet = 3
}
elseif(($masterSubnetSize -gt 7) -and ($masterSubnetSize -lt 16))
{
    $CurrentOctet = 3
    $LastOctet = 2
}

$currentOctetIP = GetCurrentOctetStartingIP $CurrentOctet $StartingIP
$StartingIPOctets = $StartingIP.Split(".")
$StartingFirstOctet = $StartingIPOctets[0]
$StartingSecondOctet = $StartingIPOctets[1]
$StartingThirdOctet = $StartingIPOctets[2]
$StartingFourthOctet = $StartingIPOctets[3]

$currentOctetPrefix = "$StartingFirstOctet.$StartingSecondOctet"
$currentOctetSuffix = $StartingFourthOctet

#Write-Host $CurrentOctetIP
$subnetObjects = @()
$subnetCount = 0
$secondOctet = [int]$StartingSecondOctet


while(([int]$subnetCount -lt [int]$numberOfSubnets))
{
    #Write-Host "Pre: $CurrentOctetIP"
    #Write-Host $masterSubnetSize

    if(([int]$currentOctetIP -gt 255) -and ([int]$masterSubnetSize -lt 16))
    {
        #Write-Host "Inside"
        
        $currentOctetIP = 0
        [int]$secondOctet++ | Out-Null
        $currentOctetPrefix = "$StartingFirstOctet.$secondOctet"
    }

    #Write-Host "Post: $CurrentOctetIP"

    $newSubnet = $null
    $subnetIP="$currentOctetPrefix.$CurrentOctetIP.$CurrentOctetSuffix"
    $newSubnet = "$subnetIP/$subnetSize"
    $newSubnetObject = New-Object -TypeName PSObject -Property @{
        'SubnetRange' = $newSubnet
        'IsAvailable' = $true
        'AssignedToAccount' = $null
    }
    $subnetObjects += $newSubnetObject
    [int]$CurrentOctetIP += [int]$subnetAddFactor
    [int]$subnetCount++ | Out-Null
}

$filename = "$($StartingIP)_$($subnetSize)-subnets.json"

if(Test-Path $filename)
{
    Remove-Item $filename -Force
}

$subnetObjects | ConvertTo-Json | Out-File $filename