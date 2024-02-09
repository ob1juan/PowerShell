# RUN AS ADMINISTRATOR
# https://nils.schimmelmann.us/post/153541254987/intel-smart-response-technology-vs-windows-10
#Tested with one SSD and two HDD
#
[CmdletBinding()]
param (
    [string]
    $StoragePoolName = "Files.Pool",
    [string]
    $SSDTierName = "SSDMirrorTier",
    [string]
    $HDDTierName = "HDDMirrorTier",
    [string]
    $HDDParityTierName = "HDDParityTier",
    [string]
    $virtualDiskName = "Files.VDisk",
    [string]
    $DriveTierResiliency = "Mirror",
    [string]
    $TieredDriveLetter = "B",
    [string]
    $TieredDriveLabel = "Files",
    [int64]
    $SSDTierSize,
    [int64]
    $HDDTierSize,
    [int64]
    $HDDParityTierSize,
    [bool]
    $createTieredDisks = $false
)

#Simple = striped.  Mirror only works if both can mirror AFIK
#https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/dn387076(v=ws.11)
#https://docs.microsoft.com/en-us/powershell/module/storage/set-resiliencysetting?view=win10-ps
#https://docs.microsoft.com/en-us/powershell/module/storage/set-storagepool?view=win10-ps

#Override the default sizing here - useful if have two different size SSDs or HDDs - set to smallest of pair
#These must be Equal or smaller than the disk size available in that tier SSD and HDD
#SSD:cache  -    HDD:data
#set to null so copy/paste to command prompt doesn't have previous run values

#Drives cannot always be fully allocated - probably broken for drives < 10GB
$UsableSpace = 0.99
$PhysicalDisks = Get-PhysicalDisk -CanPool $True 
$HDDs = $PhysicalDisks | Where MediaType -eq HDD
$SSDs = $PhysicalDisks | Where MediaType -eq SSD
#Uncomment and put your HDD type here if it shows up as unspecified with "Get-PhysicalDisk -CanPool $True
#    If your HDDs show up as Unspecified instead of HDD
$UseUnspecifiedDriveIsHDD = "Yes"
if ($null -eq (Get-StoragePool -FriendlyName $StoragePoolName)){
    Write-Output "Storage Pool does not exist: $StoragePoolName"

    $PhysicalDisks| ft FriendlyName, OperationalStatus, Size, MediaType

    #Store all physical disks that can be pooled into a variable, $PhysicalDisks
    #    This assumes you want all raw / unpartitioned disks to end up in your pool - 
    #    Add a clause like the example with your drive name to stop that drive from being included
    #    Example  " | Where FriendlyName -NE "ATA LITEONIT LCS-256"
    if ($UseUnspecifiedDriveIsHDD -ne $null){
        $DisksToChange = (Get-PhysicalDisk -CanPool $True | where MediaType -eq Unspecified)
        $DisksToChange | Set-PhysicalDisk -MediaType HDD
        $HDDs = $DisksToChange
        $PhysicalDisks = Get-PhysicalDisk -CanPool $True
        # show the type changed
        $PhysicalDisks | ft FriendlyName, OperationalStatus, Size, MediaType
    }

    if ($null -eq (Get-PhysicalDisk -CanPool $True | Where MediaType -NE UnSpecified)){
        throw "Abort! No physical Disks available"
    }       

    #Create a new Storage Pool using the disks in variable $PhysicalDisks with a name of My Storage Pool
    $SubSysName = (Get-StorageSubSystem).FriendlyName
    New-StoragePool -PhysicalDisks $PhysicalDisks -StorageSubSystemFriendlyName $SubSysName -FriendlyName $StoragePoolName
    #View the disks in the Storage Pool just created
    Get-StoragePool -FriendlyName $StoragePoolName | Get-PhysicalDisk | Select FriendlyName, MediaType
} 
else 
{
        Write-Output "Storage Pool already exists: $StoragePoolName"
        $HDDs = get-StoragePool -FriendlyName files.pool|Get-PhysicalDisk |Where-Object {$_.MediaType -eq "HDD"}
        Get-StorageTier |Remove-StorageTier -Confirm:$false
}
#Set the number of columns used for each resiliency - This setting assumes you have at least 2-SSD and 2-HDD
# Get-StoragePool $StoragePoolName | Set-ResiliencySetting -Name Simple -NumberOfColumnsDefault 2
# Get-StoragePool $StoragePoolName | Set-ResiliencySetting -Name Mirror -NumberOfColumnsDefault 1

# you can end up with different number of columns in SSD - Ex: With Simple 1SSD and 2HDD could end up with SSD-1Col, HDD-2Col

$numColsHDD = ($HDDs.Count)
Write-Host "Cols=" $numColsHDD
$interleave = "16KB"
$allocationUnitSize = "64KB"

if ($createTieredDisks -eq $true){

    #Create two tiers in the Storage Pool created. One for SSD disks and one for HDD disks
    $SSDTier = New-StorageTier -StoragePoolFriendlyName $StoragePoolName -FriendlyName $SSDTierName -MediaType SSD -ResiliencySettingName Mirror -FaultDomainAwareness PhysicalDisk
    $HDDTier = New-StorageTier -StoragePoolFriendlyName $StoragePoolName -FriendlyName $HDDTierName -MediaType HDD -ResiliencySettingName Mirror -FaultDomainAwareness PhysicalDisk
    $HDDParityTier = New-StorageTier -StoragePoolFriendlyName $StoragePoolName -FriendlyName $HDDParityTierName -MediaType HDD -Interleave $interleave -FaultDomainAwareness PhysicalDisk -NumberOfColumns $numColsHDD -ResiliencySettingName Parity

    #Can override by setting sizes at top
    if ($SSDTierSize -eq $null){
        $SSDTierSize = (Get-StorageTierSupportedSize -FriendlyName $SSDTierName -ResiliencySettingName $DriveTierResiliency).TierSizeMax
        $SSDTierSize = [int64]($SSDTierSize * $UsableSpace)
    }
    if ($HDDTierSize -eq $null){
        $HDDTierSize = (Get-StorageTierSupportedSize -FriendlyName $HDDTierName -ResiliencySettingName $DriveTierResiliency).TierSizeMax 
        $HDDTierSize = [int64]($HDDTierSize * $UsableSpace)
    }
    if ($null -eq $HDDParityTierSize){
        $HDDParityTierSize = (Get-StorageTierSupportedSize -FriendlyName $HDDParityTierName -ResiliencySettingName Parity).TierSizeMax 
        $HDDParityTierSize = [int64]($HDDParityTierSize * $UsableSpace)
    }
    Write-Output "TierSizes: ( $SSDTierSize , $HDDTierSize, $HDDParityTierSize )"

    Write-Output "Creating tiered disks"
    #Create a new Virtual Disk using the two tiers created above
    New-VirtualDisk -StoragePoolFriendlyName $StoragePoolName -FriendlyName $virtualDiskName -StorageTiers @($SSDTier, $HDDParityTier) -StorageTierSizes @($SSDTierSize, $HDDParityTierSize) -ProvisioningType Fixed
}
else{
    Write-Output "Creating untiered disks"
    #Create a new Virtual Disk using the two tiers created above
    New-VirtualDisk -StoragePoolFriendlyName $StoragePoolName -FriendlyName $virtualDiskName -UseMaximumSize -NumberOfColumns $numColsHDD -FaultDomainAwareness PhysicalDisk -Interleave $interleave -MediaType HDD -ResiliencySettingName Parity -ProvisioningType Fixed
}

# initialize the disk, format and mount as a single volume
Write-Output "preparing volume"
Get-VirtualDisk $virtualDiskName | Get-Disk | Initialize-Disk -PartitionStyle GPT
# This will be Partition 2.  Storage pool metadata is in Partition 1
Get-VirtualDisk $virtualDiskName | Get-Disk | New-Partition -DriveLetter $TieredDriveLetter -UseMaximumSize 
Initialize-Volume -DriveLetter $TieredDriveLetter -FileSystem NTFS -Confirm:$false -NewFileSystemLabel $TieredDriveLabel -AllocationUnitSize $allocationUnitSize
Get-Volume -DriveLetter $TieredDriveLetter

Write-Output "Operation complete"