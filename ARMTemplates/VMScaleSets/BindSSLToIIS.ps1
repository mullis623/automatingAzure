[CmdletBinding()]
param (
    [string]$IISSiteName,
    [string]$CertSubjectName
)

# Can be added if not using image with IIS Preinstalled
#Add-WindowsFeature Web-Server -IncludeManagementTools
New-WebBinding -Name $IISSiteName -Protocol https -Port 443
Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject.ToLower().IndexOf($CertSubjectName.ToLower()) -gt 0} | New-Item -Path IIS:\SslBindings\!443