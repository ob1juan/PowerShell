<#
.SYNOPSIS
    Backs up SD card contents to a structured destination directory.

.PARAMETER inputDirs
    One or more source directories to back up (e.g. the SD card root).

.PARAMETER outputDir
    Destination root directory. Defaults to a platform-specific path when omitted.

.PARAMETER format
    When $true, prompts to format the source drive after a successful backup.

.PARAMETER copyToPhotosInProgress
    Also copy imported files to a Photos-InProgress volume.

.PARAMETER photosInProgressVolumePath
    Override the default Photos-InProgress volume path.

.PARAMETER dateFilter
    Limit which files are imported by their last-write date. Accepts the following
    shortcuts (case-insensitive) or an explicit date string (e.g. "2024-01-15"):

        Today          – files written today
        Past Week      – files written in the last 7 days
        Past Month     – files written within the last calendar month
        Past 3 Months  – files written in the last 3 calendar months
        Past Year      – files written in the last 12 calendar months

    When omitted, all files are processed (existing behaviour).
    Filtering is based on each file's LastWriteTime.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $inputDirs=@(),
    [string]
    $outputDir,
    [bool]
    $format = $false,
    [switch]
    $copyToPhotosInProgress,
    [string]
    $photosInProgressVolumePath,
    # Optional date filter. Accepts shortcuts (Today, Past Week, Past Month,
    # Past 3 Months, Past Year) or an explicit date string (e.g. "2024-01-15").
    [string]
    $dateFilter
)
$date = Get-Date
$global:OS
$global:separator
$global:photosInProgressDir

if ($IsMacOS){
    #Write-Host "MacOS"
    $global:OS = "MacOS"
    $global:separator = "/"
    if ($null -eq $outputDir -or $outputDir -eq ""){
        $outputDir = "/Volumes/MediaFiles/Card Backup"
    } 
    if ($null -eq $photosInProgressVolumePath -or $photosInProgressVolumePath -eq ""){
        $photosInProgressVolumePath = "'/Volumes/Photos-InProgress/Photo Library/In Progress/'"
    }
}elseif ($IsWindows){
    #Write-Host "Windows"
    $global:OS = "Windows"
    $global:separator = "\"
    if ($null -eq $outputDir -or $outputDir -eq ""){
        $outputDir = "S:\Card Backup"
    }
    if ($null -eq $photosInProgressVolumePath -or $photosInProgressVolumePath -eq ""){
        $photosInProgressVolumePath = "e:\Photos-InProgress\Photo Library\In Progress\"
    }
}elseif ($IsLinux){
    #Write-Host "Linux"
    $global:OS = "Linux"
    $global:separator = "/"
    if ($null -eq $outputDir -or $outputDir -eq ""){
        $outputDir = "/mnt/MediaFiles/Card Backup"
    }
    if ($null -eq $photosInProgressVolumePath -or $photosInProgressVolumePath -eq ""){
        $photosInProgressVolumePath = "/mnt/Photos-InProgress"
    }
}else{
    Write-Host "What is this running on?"
}

if ($copyToPhotosInProgress){
    if ($null -eq $photosInProgressVolumePath -or $photosInProgressVolumePath -eq ""){
        throw "Could not determine a Photos-InProgress volume path for this operating system."
    }

    $photosInProgressVolumePath = $photosInProgressVolumePath.TrimEnd([char[]]@( '\', '/' ))
    if ($photosInProgressVolumePath -match "(?i)(^|[\\/])Temp Card Backup$"){
        $global:photosInProgressDir = $photosInProgressVolumePath
    }else{
        $global:photosInProgressDir = $photosInProgressVolumePath + $global:separator + "Card Backup"
    }
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

# Resolves the $dateFilter parameter to a [DateTime] start date.
# Returns $null when no filter is specified (all files are processed).
# Supported shortcuts: Today, Past Week, Past Month, Past 3 Months, Past Year.
# An explicit date string (e.g. "2024-01-15") is also accepted.
function getDateFilterStart {
    param([string]$filter)

    if ([string]::IsNullOrWhiteSpace($filter)) {
        return $null
    }

    $today = (Get-Date).Date

    switch -Wildcard ($filter.ToLower().Trim()) {
        "today"          { return $today }
        "past week"      { return $today.AddDays(-7) }
        "pastweek"       { return $today.AddDays(-7) }
        "past month"     { return $today.AddMonths(-1) }
        "pastmonth"      { return $today.AddMonths(-1) }
        "past 3 months"  { return $today.AddMonths(-3) }
        "past3months"    { return $today.AddMonths(-3) }
        "past year"      { return $today.AddYears(-1) }
        "pastyear"       { return $today.AddYears(-1) }
        default {
            # Try to parse as an explicit date
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($filter, [ref]$parsed)) {
                return $parsed.Date
            }
            throw "Invalid -dateFilter value: '$filter'. " +
                  "Use Today, 'Past Week', 'Past Month', 'Past 3 Months', 'Past Year', " +
                  "or an explicit date string such as '2024-01-15'."
        }
    }
}

# Resolve the date filter once; $null means no filtering (all files are processed).
$filterStartDate = getDateFilterStart -filter $dateFilter
if ($null -ne $filterStartDate) {
    Write-Host "Date filter active: only files with LastWriteTime on or after $($filterStartDate.ToString('yyyy-MM-dd')) will be imported."
}

function ensureDirectory($folderPath) {
    if (-not (Test-Path $folderPath)) {
        try {
            New-Item $folderPath -ItemType Directory -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host -ForegroundColor red "Could not create $folderPath. $($_.Exception.Message)"
            return $false
        }
    }

    return $true
}

function getMirroredFilePath($filePath, $sourceRoot, $destinationRoot) {
    $trimmedSourceRoot = $sourceRoot.TrimEnd([char[]]@( '\', '/' ))
    $trimmedDestinationRoot = $destinationRoot.TrimEnd([char[]]@( '\', '/' ))
    $relativeFilePath = $filePath.Substring($trimmedSourceRoot.Length).TrimStart([char[]]@( '\', '/' ))

    return $trimmedDestinationRoot + $global:separator + $relativeFilePath
}

function copyVerifiedFile($file, $filePath, $sourceHash, $targetName) {
    $fileName = $file.Name
    $fileSize = (Get-Item $file).Length
    $folderPath = Split-Path -Path $filePath -Parent

    if (-not (ensureDirectory -folderPath $folderPath)) {
        return [pscustomobject]@{
            Success = $false
            Message = "Could not create $folderPath"
        }
    }

    $destHash = (Get-FileHash $filePath -Algorithm md5 -ErrorAction SilentlyContinue).Hash

    if ((-not (Test-Path $filePath)) -or ($sourceHash -ne $destHash)) {
        try {
            $fileCopyStart = Get-Date
            Copy-Item $file.FullName -Destination $filePath -ErrorAction Stop
            $fileCopyEnd = Get-Date
            $destHash = (Get-FileHash $filePath -Algorithm md5).Hash
            if ($sourceHash -eq $destHash){
                $timeTaken = ($fileCopyEnd - $fileCopyStart).TotalSeconds
                if ($timeTaken -gt 0){
                    $speedMBps = ($fileSize / 1MB) / $timeTaken
                }else{
                    $speedMBps = 0
                }

                Write-Output "$targetName Transfer Speed: $([math]::Round($speedMBps, 2)) MB/s"
                Write-Host -ForegroundColor Green $filePath "copied and verified. Time:" (New-TimeSpan -Start $fileCopyStart -End $fileCopyEnd) " Speed: " ($speedMBps) "Size: " ($fileSize / 1MB) "MB"

                return [pscustomobject]@{
                    Success = $true
                    Message = $null
                }
            }else{
                $message = "checksum does not match $fileName"
                Write-Host -ForegroundColor red $message

                return [pscustomobject]@{
                    Success = $false
                    Message = $message
                }
            }
        }
        catch {
            $message = "Could not copy file $fileName to $filePath. $($_.Exception.Message)"
            Write-Host -ForegroundColor red $message

            return [pscustomobject]@{
                Success = $false
                Message = $message
            }
        }    
    }else {
        Write-Host -ForegroundColor DarkGreen "$fileName already exists in $targetName."

        return [pscustomobject]@{
            Success = $true
            Message = "File already exists"
        }
    }
}

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
    $fileSize = (Get-Item $file).Length

    $logObj = New-Object psobject
    $logObj | Add-Member -MemberType NoteProperty -Name "StartDate" -Value (Get-Date)
    $logObj | Add-Member -MemberType NoteProperty -Name "inputDir" -Value $inputDir
    $logObj | Add-Member -MemberType NoteProperty -Name "File" -Value $fileName
    $logObj | Add-Member -MemberType NoteProperty -Name "FileSize" -Value $fileSize
    $logObj | Add-Member -MemberType NoteProperty -Name "Source" -Value $file.FullName
    $logObj | Add-Member -MemberType NoteProperty -Name "Destination" -Value $filePath
    $logObj | Add-Member -MemberType NoteProperty -Name "Success" -Value $null
    $logObj | Add-Member -MemberType NoteProperty -Name "Message" -Value $null
    $logObj | Add-Member -MemberType NoteProperty -Name "PhotosInProgressDestination" -Value $null
    $logObj | Add-Member -MemberType NoteProperty -Name "PhotosInProgressSuccess" -Value $null
    $logObj | Add-Member -MemberType NoteProperty -Name "PhotosInProgressMessage" -Value $null

    $primaryCopyResult = copyVerifiedFile -file $file -filePath $filePath -sourceHash $sourceHash -targetName "Primary destination"
    $logObj.Success = $primaryCopyResult.Success
    $logObj.Message = $primaryCopyResult.Message

    if ($copyToPhotosInProgress){
        $photosInProgressFilePath = getMirroredFilePath -filePath $filePath -sourceRoot $outputDir -destinationRoot $global:photosInProgressDir
        $photosInProgressCopyResult = copyVerifiedFile -file $file -filePath $photosInProgressFilePath -sourceHash $sourceHash -targetName "Photos-InProgress destination"

        $logObj.PhotosInProgressDestination = $photosInProgressFilePath
        $logObj.PhotosInProgressSuccess = $photosInProgressCopyResult.Success
        $logObj.PhotosInProgressMessage = $photosInProgressCopyResult.Message

        if (-not $photosInProgressCopyResult.Success){
            $logObj.Success = $false
            $messages = @($logObj.Message, $photosInProgressCopyResult.Message) | Where-Object { $null -ne $_ -and $_ -ne "" }
            $logObj.Message = $messages -join "; "
        }
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

    # Apply date filter when -dateFilter was specified.
    # Filtering uses LastWriteTime (the date content was last written, which on
    # camera cards corresponds to when the photo/video was captured).
    if ($null -ne $filterStartDate) {
        $files = $files.Where({ $_.LastWriteTime.Date -ge $filterStartDate })
        Write-Host "Date filter applied: $($files.Count) file(s) on or after $($filterStartDate.ToString('yyyy-MM-dd')) found in $inputDir."
    }

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
    if ($copyToPhotosInProgress){
        Write-Host "Also copying imported files to $global:photosInProgressDir"
    }
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

