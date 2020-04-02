param
(
    [string]$subnetSize,
    [string]$accountID
)

$filename = "$($subnetSize)_subnets.json"

$subnets = (Get-Content $filename -Raw) | ConvertFrom-Json

$firstAvailableSubnet = ($subnets | Where-Object {$_.IsAvailable -eq $true})[0]

$firstAvailableSubnet.IsAvailable = $false
$firstAvailableSubnet.AssignedToAccount = $accountID

$subnets | ConvertTo-Json | Out-File "$($filename)_updated.json"

Remove-Item $filename -Force
Rename-Item "$($filename)_updated.json" $filename

return $firstAvailableSubnet.SubnetRange
