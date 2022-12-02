[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $region = '<Az_Region>',
    [Parameter()]
    [String]
    $resourceGroup = '<RG_Name>',
    [Parameter()]
    [String]
    $subscription = '<Subscription Name>',
    [Parameter()]
    [String]
    $storageSyncName = "<my_storage_sync_service>",
    [Parameter()]
    [String]
    $syncGroupName = "<my-sync-group>",
    [Parameter()]
    [String]
    $storageAccountName = "<my-storage-account>",
    [Parameter()]
    [String]
    $fileShareName = "<my-file-share>",
    [Parameter()]
    [String]
    $serverEndpointPath = "<your-server-endpoint-path>",
    [Parameter()]
    [bool]
    $createServerEndPoint = $false,
    [Parameter()]
    [bool]
    $cloudTieringDesired = $true
)

Connect-AzAccount -Environment AzureUSGovernment
Set-AzContext -Subscription $subscription

# Check to ensure Azure File Sync is available in the selected Azure
# region.
$regions = @()
Get-AzLocation | ForEach-Object { 
    if ($_.Providers -contains "Microsoft.StorageSync") { 
        $regions += $_.Location 
    } 
}

if ($regions -notcontains $region) {
    throw [System.Exception]::new("Azure File Sync is either not available in the selected Azure Region or the region is mistyped.")
}

# Check to ensure resource group exists and create it if doesn't
Write-Host -ForegroundColor Gray "Checking for Resource Group: $resourceGroup"
$resourceGroups = @()
Get-AzResourceGroup | ForEach-Object { 
    $resourceGroups += $_.ResourceGroupName 
}

if ($resourceGroups -notcontains $resourceGroup) {
    Write-Host -ForegroundColor Yellow "Creating Resourse Group: $resourceGoup"
    New-AzResourceGroup -Name $resourceGroup -Location $region
}

Write-Host -ForegroundColor Yellow "Creating Storage Sync Service: $storageSyncName"
try {
    $storageSync = New-AzStorageSyncService -ResourceGroupName $resourceGroup -Name $storageSyncName -Location $region
    Write-Host -ForegroundColor Green "Created Storage Sync Service: $storageSyncName"
}
catch {
    throw [System.Exception]::new("Could not create Storage Sync Service.")
}

Write-Host -ForegroundColor Yellow "Creating Sync Group: $syncGroupName"
try {
    $syncGroup = New-AzStorageSyncGroup -ParentObject $storageSync -Name $syncGroupName
    Write-Host -ForegroundColor Green "Created Sync Group: $syncGroupName"
}
catch {
    throw [System.Exception]::new("Could not create Storage Sync Group.")
}

$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup | Where-Object {
    $_.StorageAccountName -eq $storageAccountName
}

if ($storageAccount -eq $null) {
    $storageAccount = New-AzStorageAccount `
        -Name $storageAccountName `
        -ResourceGroupName $resourceGroup `
        -Location $region `
        -SkuName Standard_LRS `
        -Kind StorageV2 `
        -EnableHttpsTrafficOnly:$true
}

$fileShare = Get-AzStorageShare -Context $storageAccount.Context | Where-Object {
    $_.Name -eq $fileShareName -and $_.IsSnapshot -eq $false
}

if ($fileShare -eq $null) {
    $fileShare = New-AzStorageShare -Context $storageAccount.Context -Name $fileShareName
}

# Create the cloud endpoint
if ($createServerEndPoint) {
    <# Action to perform if the condition is true #>
    New-AzStorageSyncCloudEndpoint `
        -Name $fileShare.Name `
        -ParentObject $syncGroup `
        -StorageAccountResourceId $storageAccount.Id `
        -AzureFileShareName $fileShare.Name

        $volumeFreeSpacePercentage = <your-volume-free-space>
        # Optional property. Choose from: [NamespaceOnly] default when cloud tiering is enabled. [NamespaceThenModifiedFiles] default when cloud tiering is disabled. [AvoidTieredFiles] only available when cloud tiering is disabled.
        $initialDownloadPolicy = "NamespaceOnly"
        $initialUploadPolicy = "Merge"
        # Optional property. Choose from: [Merge] default for all new server endpoints. Content from the server and the cloud merge. This is the right choice if one location is empty or other server endpoints already exist in the sync group. [ServerAuthoritative] This is the right choice when you seeded the Azure file share (e.g. with Data Box) AND you are connecting the server location you seeded from. This enables you to catch up the Azure file share with the changes that happened on the local server since the seeding.
        
        if ($cloudTieringDesired) {
            # Ensure endpoint path is not the system volume
            $directoryRoot = [System.IO.Directory]::GetDirectoryRoot($serverEndpointPath)
            $osVolume = "$($env:SystemDrive)\"
            if ($directoryRoot -eq $osVolume) {
                throw [System.Exception]::new("Cloud tiering cannot be enabled on the system volume")
            }
        
            # Create server endpoint
            New-AzStorageSyncServerEndpoint `
                -Name $registeredServer.FriendlyName `
                -SyncGroup $syncGroup `
                -ServerResourceId $registeredServer.ResourceId `
                -ServerLocalPath $serverEndpointPath `
                -CloudTiering `
                -VolumeFreeSpacePercent $volumeFreeSpacePercentage `
                -InitialDownloadPolicy $initialDownloadPolicy `
                -InitialUploadPolicy $initialUploadPolicy
        } else {
            # Create server endpoint
            New-AzStorageSyncServerEndpoint `
                -Name $registeredServer.FriendlyName `
                -SyncGroup $syncGroup `
                -ServerResourceId $registeredServer.ResourceId `
                -ServerLocalPath $serverEndpointPath `
                -InitialDownloadPolicy $initialDownloadPolicy
        }
}