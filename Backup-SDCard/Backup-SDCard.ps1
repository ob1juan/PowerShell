[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $inputDirs=@(),
    [string]
    $outputDir,
    [bool]
    $format = $false
)
$date = Get-Date
$global:OS
$global:separator

if ($IsMacOS){
    #Write-Host "MacOS"
    $global:OS = "MacOS"
    $global:separator = "/"
    if ($null -eq $outputDir -or $outputDir -eq ""){
        $outputDir = "/Volumes/MediaFiles/Card Backup"
    } 
}elseif ($IsWindows){
    #Write-Host "Windows"
    $global:OS = "Windows"
    $global:separator = "\"
    if ($null -eq $outputDir -or $outputDir -eq ""){
        $outputDir = "S:\Card Backup"
    }
}elseif ($IsLinux){
    #Write-Host "Linux"
    $global:OS = "Linux"
    $global:separator = "/"
    if ($null -eq $outputDir -or $outputDir -eq ""){
        $outputDir = "/mnt/MediaFiles/Card Backup"
    }
}else{
    Write-Host "What is this running on?"
}

$global:dngConverter
$global:rawExts = @(
    ".cr2",
    ".cr3",
    ".arw",
    ".raf",
    ".raw",
    ".rwl",
    ".dng",
    ".nef",
    ".nrw",
    ".orf",
    ".rw2",
    ".pef",
    ".srw",
    ".srf",
    ".sr2",
    ".kdc",
    ".dcr",
    ".mrw",
    ".erf",
    ".3fr"
)
$global:videoExts = @(
    ".mov",
    ".mp4",
    ".wmv",
    ".m4v",
    ".lrv",
    ".avi",
    ".mts",
    ".m2ts",
    ".mpg",
    ".mpeg",
    ".3gp",
    ".3g2",
    ".mkv",
    ".flv",
    ".webm",
    ".vob",
    ".ogv",
    ".ogg",
    ".qt",
    ".asf",
    ".insv",
    ".insp"
)
$global:tifExts =@(
    ".tif",
    ".tiff",
    ".psd",
    ".psb"
)
$global:jpgExts =@(
    ".jpg",
    ".jpeg",
    ".jpe",
    ".jif",
    ".jfif",
    ".jfi"
)
$global:heifExts =@(
    ".hif",
    ".heif",
    ".heic"
)
$global:audioExts = @(
    ".mp3",
    ".wav",
    ".aac"
)

$global:cameraProfiles =@(
    @{
        "brand" = "Sony" 
        "ext" = ".dat"
    },
    @{
        "brand" = "Leica"
        "ext" = ".lcs"
    }
)

$global:resumeLogPath = "~/Backup-SDCard-Resume.log"
$global:backupLog = @()
$global:backupLogPath = "~/Backup-SDCard-Log.log"
$global:totalSize = 0

function copyFileOfType($inputDir, $file, $type, $parent) {
    # find when it was created
    $dateCreated = $file.CreationTime
    $dateModified = $file.LastWriteTime
    $year = $dateCreated.Year
    $day = (Get-Date -Date $dateCreated).ToString("dd")
    $month = (Get-Date -Date $dateCreated).ToString("MM")
    $fileName = $file.Name

    # Build up a path to where the file should be copied to (e.g. 1_2_Jan) use numbers for ordering and inc month name to make reading easier.
    if (($null -eq $parent) -or ($type -eq "other")){
        $parent = "other"
        $type = "unknown"
    }

    $folderName = $outputDir + $global:separator + $year + $global:separator + $year + "-" + $month + "-" + $day + $global:separator + $parent + $global:separator `
         + $type + $global:separator
	
    $modifiedYear = $dateModified.Year
    $modifiedDay = (Get-Date -Date $dateModified).ToString("dd")
    $modifiedMonth = (Get-Date -Date $dateModified).ToString("MM")

    $modifiedFolderName = $outputDir + $global:separator + $modifiedYear + $global:separator + $modifiedYear + "-" + $modifiedMonth + "-" + $modifiedDay + $global:separator + $parent + $global:separator `
         + $type + $global:separator

    if ($type -eq "profile"){
        $cameraProfile = $global:cameraProfiles | Where-Object {$_.ext -eq [IO.Path]::GetExtension($fileName)}
        $cameraBrand = $cameraProfile.brand

        $filePWD = $file.FullName -replace $inputDir, ""
        $profilePath = $filePWD -replace $fileName, ""

        $folderName = $outputDir + $global:separator + "Profiles" + $global:separator + $cameraBrand +  $global:separator + $year + $global:separator + $year + "-" + $month + "-" + $day + $global:separator + $profilePath
    }

    #check if in wrong folder
    if ($modifiedYear -ne $year -or $modifiedMonth -ne $month -or $modifiedDay -ne $day) {
        Write-Host -ForegroundColor Yellow "File $fileName was modified on $modifiedYear-$modifiedMonth-$modifiedDay."
        Write-Host -ForegroundColor Yellow "Moving to modified folder: $modifiedFolderName"

        $wrongFolderName = $folderName
        $folderName = $modifiedFolderName
        # Check if the modified folder exists, if it doesn't create it
        if (-not (Test-Path $folderName)) { 
            try {
                new-item $folderName -itemtype directory -ErrorAction Stop
            }
            catch {
                Write-Host -ForegroundColor red "Could not create $folderName. $_.Exception.Message" 
            }
        }else{
            if ((Test-Path -Path $wrongFolderName) -and (Get-ChildItem -Path $wrongFolderName -Filter $fileName -File -ErrorAction SilentlyContinue)){
                $file = Get-ChildItem -Path $wrongFolderName -Filter $fileName -File -ErrorAction SilentlyContinue
                Write-Host -ForegroundColor DarkGreen "$fileName already exists in modified folder. Moving it to $folderName"
                # Move the file to the modified folder
                try {
                    Move-Item -Path $file.FullName -Destination $folderName -Force -ErrorAction Stop
                    write-host -ForegroundColor Green "Moved $fileName to $folderName"
                }
                catch {
                    Write-Host -ForegroundColor red "Could not move $fileName to $folderName. $_.Exception.Message"
                }
                return
            }else {
            # Check if the folder exists, if it doesn't create it
                if (-not (Test-Path $folderName)) { 
                    try {
                        new-item $folderName -itemtype directory -ErrorAction Stop
                    }
                    catch {
                        Write-Host -ForegroundColor red "Could not create $folderName. $_.Exception.Message" 
                    }
                }
            }
        }
    }else{
    # Check if the folder exists, if it doesn't create it
        if (-not (Test-Path $folderName)) { 
            try {
                new-item $folderName -itemtype directory -ErrorAction Stop
            }
            catch {
                Write-Host -ForegroundColor red "Could not create $folderName. $_.Exception.Message" 
            }
        }
    }


    # build up the full path inc filename
    $filePath = $folderName + $fileName
    #Write-host -ForegroundColor DarkCyan $parent
    #Write-Host -ForegroundColor Cyan $filePath

    # If it's not already copied, copy it
    $sourceHash = (get-filehash $file.FullName -Algorithm md5).Hash
    $destHash = (get-filehash $filePath -Algorithm md5 -ErrorAction SilentlyContinue).Hash
    $fileSize = (Get-Item $file).Length

    $logObj = New-Object psobject
    $logObj | Add-Member -MemberType NoteProperty -Name "StartDate" -Value (Get-Date)
    $logObj | Add-Member -MemberType NoteProperty -Name "inputDir" -Value $inputDir
    $logObj | Add-Member -MemberType NoteProperty -Name "File" -Value $fileName
    $logObj | Add-Member -MemberType NoteProperty -Name "FileSize" -Value $fileSize
    $logObj | Add-Member -MemberType NoteProperty -Name "Source" -Value $file.FullName
    $logObj | Add-Member -MemberType NoteProperty -Name "Destination" -Value $filePath
    $logObj | Add-Member -MemberType NoteProperty -Name "Success" -Value $fileSuccess
    $logObj | Add-Member -MemberType NoteProperty -Name "Message" -Value $fileError

    if ((-not (Test-Path $filePath)) -or ($sourceHash -ne $destHash)) {
        try {
            #Write-Host -ForegroundColor Yellow "sourceHash $sourceHash / destHash $destHash"
            $fileCopyStart = Get-Date
            Copy-Item $file.FullName -Destination $filePath -ErrorAction Stop
            $fileCopyEnd = Get-Date
            #Write-Host -ForegroundColor Green "$fileName"
            $destHash = (get-filehash $filePath -Algorithm md5).Hash
            if ($sourceHash -eq $destHash){
                $sizeBytes = (Get-Item $file).Length
                $timeTaken = ($fileCopyEnd - $fileCopyStart).TotalSeconds
                $speedMBps = ($sizeBytes / 1MB) / $timeTaken

                Write-Output "Transfer Speed: $([math]::Round($speedMBps, 2)) MB/s"
                Write-Host -ForegroundColor Green $filePath "copied and verified. Time:" (New-TimeSpan -Start $fileCopyStart -End $fileCopyEnd) " Speed: " ($speedMBps) "Size: " ($fileSize / 1MB) "MB"
                $logObj.Success = $true
            }else{
                $logObj.Success = $false
                $logObj.Message = "checksum does not match $fileName. $_.Exception.Message"

                Write-Host -ForegroundColor red "checksum does not match $fileName. $_.Exception.Message"
            }
        }
        catch {
            $logObj.Success = $false
            $logObj.Message = "Could not copy file $fileName. $_.Exception.Message"
            Write-Host -ForegroundColor red "Could not copy file $fileName. $_.Exception.Message"
        }    
    }else {
        Write-Host -ForegroundColor DarkGreen "$fileName already exists."
        $logObj.Success = $true
        $logObj.Message = "File already exists"
    }

    if ($type -eq "raw"){
        if($rawFolders -notcontains $folderName){
            $rawFolders += $folderName
        }
    }
    $logObj | Add-Member -MemberType NoteProperty -Name "EndDate" -Value (Get-Date)
    $global:backupLog += $logObj
}

function backupSource($inputDir){
    # get all files inside all folders and sub folders
    $files = Get-ChildItem $inputDir -file -Recurse

    #$sourceDriveLetter = (Get-Volume (($inputDir) -split ":")[0]).DriveLetter
    $rawFolders = @()
    $fileCount = 0
    $rawFileCount = 0
    
    # Create reusable func for changing dir based on type

    if (Test-Path ($global:resumeLogPath)) {
        $resumeFiles = Import-Csv -Path $global:resumeLogPath -ErrorAction SilentlyContinue
        if ($resumeFiles.count -gt 0){
            $origFiles = $files
            $resumeBackup = Read-Host "Type Resume to continue where last backup failed. Or Enter/Return to continue."
            if ($resumeBackup -eq "Resume"){
                $files = $resumeFiles
            }
        }
    }

    foreach ($f in $files) { 
        # get the files name
        $fileCount++
        $fileName = $f.Name
        $parent = $f.Directory.BaseName
        $fileExt = [IO.Path]::GetExtension($fileName) 
        $perct = ($fileCount / $files.count) * 100
        Write-Progress -Activity "Progress" -Status "Copying" -PercentComplete $perct

        if ( [IO.Path]::GetExtension($fileName) -eq '.jpg' ) {
            copyFileOfType -inputDir $inputDir -file $f -type "jpg" -parent $parent
            #Write-Host "JPG: $f"
        }
        elseif ($global:jpgExts -contains $fileExt) {
            copyFileOfType -inputDir $inputDir -file $f -type "jpg" -parent $parent
            #Write-Host "JPG: $f"
        }
        elseif ($global:tifExts -contains $fileExt) {
            copyFileOfType -inputDir $inputDir -file $f -type "tif" -parent $parent
            #Write-Host "TIF: $f"
        }
        elseIf($global:heifExts -contains $fileExt){
            copyFileOfType -inputDir $inputDir -file $f -type "heif" -parent $parent
        }
        elseif ($global:rawExts -contains $fileExt) {
        #elseif ( [IO.Path]::GetExtension($fileName) -eq '.cr3' -or [IO.Path]::GetExtension($fileName) -eq '.raf') {
            copyFileOfType -inputDir $inputDir -file $f -type "raw" -parent $parent
            $rawFileCount ++
            #Write-Host "Raw: $f"
        }
        elseif ($global:videoExts -contains $fileExt) {
            copyFileOfType -inputDir $inputDir -file $f -type "video" -parent $parent
            #Write-Host "Video: $f"
        }
        elseif ($global:cameraProfiles.ext -contains $fileExt){
            copyFileOfType -inputDir $inputDir -file $f -type "profile" -parent $parent
            #Write-Host "Profile: $f"
        }
        elseif ($global:audioExts -contains $fileExt){
            copyFileOfType -inputDir $inputDir -file $f -type "audio" -parent $parent
            #Write-Host "Profile: $f"
        }
        else {
            copyFileOfType -inputDir $inputDir -file $f -type "other" -parent $parent
            #Write-Host "Other: $f"
        }    
    }

    foreach ($rawFolder in $rawFolders){
        $outFolderName = $rawFolder -replace ("raw", "rawc")
        #compressDNG -folderName $rawFolder -outFolderName $outFolderName
    }
         
<#     if ($fileSuccessCount -gt 0 -AND $fileErrorCount -eq 0 -AND $format -eq $true){
        $format = Read-Host "Type FORMAT to format the $sourceDriveLetter."
        if ($format -ceq "FORMAT"){
            $label = (Get-Volume -DriveLetter $sourceDriveLetter).FileSystemLabel
            Format-Volume -DriveLetter $sourceDriveLetter -NewFileSystemLabel $label
        }
    }  #>

    $filesNotCopied = $global:backupLog | Where-Object {$_.Success -eq $false}
    $filesNotCopied |Export-Csv -Path "~/Backup-SDCard-Resume.log" -NoTypeInformation
}

foreach ($inputDir in $inputDirs){
    write-host "Backing up $inputDir to $outputDir"
    backupSource -inputDir $inputDir
}

$global:backupLog | Export-Csv -Path $global:backupLogPath -Append -NoTypeInformation

Write-host "Script Started: " $date

foreach ($inputDir in $inputDirs){

    $log = $global:backupLog |Where-Object {$_.inputDir -eq $inputDir}
    $startDate = $log |Select-Object -First 1 -ExpandProperty StartDate
    $endDate = $log |Select-Object -Last 1 -ExpandProperty EndDate
    $fileCount = $log |Where-Object {$_.inputDir -eq $inputDir} | Measure-Object | Select-Object -ExpandProperty Count
    $fileSuccessCount = $log | Where-Object {$_.Success -eq $true} | Measure-Object | Select-Object -ExpandProperty Count
    $fileErrorCount = $log | Where-Object {$_.Success -eq $false} | Measure-Object | Select-Object -ExpandProperty Count
    $fileExistCount = $log | Where-Object {$_.Success -eq $true -and $_.Message -eq "File already exists"} | Measure-Object | Select-Object -ExpandProperty Count
    $newFilesCount = $fileCount - $fileExistCount
    $totalSize = $log | Measure-Object -Property FileSize -Sum | Select-Object -ExpandProperty Sum

    Write-Host
    Write-Host "$inputDir "
    Write-Host "Started: " $startDate
    Write-host "Ended: " $endDate
    Write-Host "Total Size: " ($totalSize / 1MB) "MB"
    Write-Host "Time taken: " (New-TimeSpan -Start $startDate -End $endDate)
    Write-Host -ForegroundColor Gray "Backup of $inputDir complete."
    Write-Host -ForegroundColor Yellow "$fileCount total files in source."
    if ($newFilesCount -gt 0) {
        Write-Host -ForegroundColor Green "$newFilesCount new files copied."
    }else{
        Write-Host -ForegroundColor Yellow "No new files copied."
    }
    Write-Host -ForegroundColor Yellow "$fileExistCount files already existed in destination."
    Write-Host -ForegroundColor Green "$fileSuccessCount total files succssfully backed up."
        
    if ($fileErrorCount -gt 0) {
        Write-Host -ForegroundColor Red "$fileErrorCount files could not be copied."
        <#
        Write-Host -ForegroundColor Red "Files not copied:"
        foreach ($file in $filesNotCopied){
            Write-Host -ForegroundColor Red $file
        }
        #>
    }
    Write-Host "------------------------------------------"
}
$endDate = Get-Date
$sizeBytes = $totalSize
$timeTaken = ($endDate - $date).TotalSeconds
$speedMBps = ($totalSize / 1MB) / $timeTaken
Write-Output "Total Transfer Speed: $([math]::Round($speedMBps, 2)) MB/s"
Write-Host "Total Time taken: " (New-TimeSpan -Start $date -End $endDate)

