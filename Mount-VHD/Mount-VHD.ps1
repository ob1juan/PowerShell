[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $vhdPath,
    [Parameter]
    [string]
    $driveLetter = "g",
    [Parameter(Mandatory=$true)]
    [string]
    $hostName,
    [Parameter(Mandatory=$true)]
    [string]
    $shareName
)

# Mount the network share
$credential = Get-Credential
$vhdRelativePath = $vhdPath -replace ".*${$driveLetter}:\", ""
New-PSDrive -Name $driveLetter -Root "\\$hostName\$vhdPath" -Persist -PSProvider "FileSystem" -Credential $credential

# Mount the VHD
$disk = Mount-DiskImage -ImagePath $vhdPath -PassThru
