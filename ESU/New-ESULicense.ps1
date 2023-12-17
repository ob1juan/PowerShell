[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$licInfoFile
)

# Install the Azure PowerShell module if not already installed
#Write-Host "Installing the Azure PowerShell module"
#Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force

# Import the Azure PowerShell module
#Write-Host "Importing the Azure PowerShell module"
#Import-Module -Name Az

# Connect to your Azure account
Write-Host "Connecting to your Azure account"
Connect-AzAccount -ErrorAction Stop

# Get an authentication token
$token = (Get-AzAccessToken).Token


function Get-LicenseInfo {
    param(
        [Parameter(Mandatory=$true)]
        [object]$licInfo
    )
    # Read the license information from the file
    $licenseName = $licInfo.licenseName
    $type = $licInfo.type
    $target = $licInfo.target
    $edition = $licInfo.edition
    $state = $licInfo.state
    $processors = $licInfo.processors
    $resourceGroupName = $licInfo.resourceGroupName
    $subscriptionId = $licInfo.subscriptionId
    $location = $licInfo.location
    
    Create-License -licenseName $licenseName -resourceGroupName $resourceGroupName -subscriptionId $subscriptionId -location $location `
        -type $type -target $target -edition $edition -state $state -processors $processors
}

function Create-License {
    param(
        [Parameter(Mandatory=$true)]
        [string]$licenseName,
        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,
        [Parameter(Mandatory=$true)]
        [string]$subscriptionId,
        [Parameter(Mandatory=$true)]
        [string]$location,
        [Parameter(Mandatory=$true)]
        [string]$type,
        [Parameter(Mandatory=$true)]
        [string]$target,
        [Parameter(Mandatory=$true)]
        [string]$edition,
        [Parameter(Mandatory=$true)]
        [string]$state,
        [Parameter(Mandatory=$true)]
        [int]$processors
    )
    # Construct the API URL
    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/licenses/" + $licenseName + "?api-version=2023-06-20-preview"
    Write-Host "url: $url"
    # Create a header with the authorization token
    $headers = @{'Authorization' = "Bearer $token"}

    # Define the body as a JSON string
    $body = @"
    { 
    "location": "$location",
        "properties": {
            "licenseDetails": {
            "state": "$state",
            "target": "$target",
            "Edition": "$edition",
            "Type": "$type",
            "Processors": $processors
            }
        }
    }      
"@
    try {
        # Invoke the REST API to create a license
        Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "Error creating license $licenseName : $_"
    }

}

# Read the license information from the file
Write-Host "Reading license information from $licInfoFile"
try {
    $AllLicInfo = Import-Csv -Path $licInfoFile -ErrorAction Stop
    foreach ($licInfo in $AllLicInfo) {
        Get-LicenseInfo -licInfo $licInfo
    }
}
catch {
    write-host -ForegroundColor Red "Error reading license information from $licInfoFile : $_"
}
Write-Host "Done"

<# 
    "licenseDetails": {
    "state": "Activated",
    "target": "Windows Server 2012",
    "Edition": "Standard",
    "Type": "vCore",
    "Processors": 12 
#>
