<#
.SYNOPSIS
    Copies JPG files from a source directory to a structured Orion destination.

.PARAMETER inputDir
    Source directory. All subfolders are searched for .jpg files.

.PARAMETER outputDir
    Destination root directory. Defaults to /Volumes/home/OneDrives/Personal/Orion
    on macOS. Required on other operating systems.

.DESCRIPTION
    Uses the Backup-SDCard layout: year/date/source-folder/jpg/filename.
    Files are grouped by LastWriteTime and verified using MD5 checksums.
    Matching destination files are skipped. Different contents are overwritten.
    Results and failed copies are recorded in ~/Orion-JPG-Log.log and
    ~/Orion-JPG-Resume.log using the Backup-SDCard CSV fields.

.EXAMPLE
    ./orion-jpg.ps1 -inputDir /Volumes/SDCard

.EXAMPLE
    ./orion-jpg.ps1 -inputDir /Volumes/SDCard -outputDir /Volumes/Photos/Orion
#>
[CmdletBinding(PositionalBinding=$false)]
param (
    [Parameter(Mandatory=$true)]
    [Alias("inputDirs")]
    [ValidateNotNullOrEmpty()]
    [string]
    $inputDir,
    [Alias("destinationDir")]
    [string]
    $outputDir
)

$date = Get-Date
if ([string]::IsNullOrWhiteSpace($outputDir)) {
    if ($IsMacOS) {
        $outputDir = "/Volumes/home/OneDrives/Personal/Orion"
    }else{
        throw "Provide -outputDir on this operating system."
    }
}

$inputDir = $inputDir.Trim([char[]]@("'", '"'))
$outputDir = $outputDir.Trim([char[]]@("'", '"'))
if (-not [System.IO.Path]::IsPathRooted($outputDir)) {
    throw "-outputDir '$outputDir' is not an absolute path. Provide a full path."
}

$sourceDirectory = Get-Item -LiteralPath $inputDir -ErrorAction Stop
if ($sourceDirectory -isnot [System.IO.DirectoryInfo]) {
    throw "-inputDir '$inputDir' is not a filesystem directory."
}
$inputDir = $sourceDirectory.FullName
$outputDir = [System.IO.Path]::GetFullPath($outputDir)
if ($inputDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar) -eq $outputDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar)) {
    throw "-inputDir and -outputDir must be different directories."
}
$destinationPrefix = $outputDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$pathComparison = if ($IsLinux) { [System.StringComparison]::Ordinal }else{ [System.StringComparison]::OrdinalIgnoreCase }

$resumeLogPath = Join-Path $HOME "Orion-JPG-Resume.log"
$backupLogPath = Join-Path $HOME "Orion-JPG-Log.log"
$script:backupLog = @()

function ensureDirectory($folderPath) {
    try {
        if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
            New-Item -Path $folderPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        return $true
    }
    catch {
        Write-Host -ForegroundColor Red "Could not create $folderPath. $($_.Exception.Message)"
        return $false
    }
}

function copyVerifiedFile($file, $filePath, $sourceHash, $targetName) {
    $fileName = $file.Name
    $fileSize = $file.Length
    $folderPath = Split-Path -Path $filePath -Parent
    if (-not (ensureDirectory -folderPath $folderPath)) {
        return [pscustomobject]@{ Success = $false; Message = "Could not create $folderPath" }
    }

    try {
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            $destHash = (Get-FileHash -LiteralPath $filePath -Algorithm MD5 -ErrorAction Stop).Hash
            if ($sourceHash -eq $destHash) {
                Write-Host -ForegroundColor DarkGreen "$fileName already exists in $targetName."
                return [pscustomobject]@{ Success = $true; Message = "File already exists" }
            }
        }

        $fileCopyStart = Get-Date
        Copy-Item -LiteralPath $file.FullName -Destination $filePath -ErrorAction Stop
        $fileCopyEnd = Get-Date
        $destHash = (Get-FileHash -LiteralPath $filePath -Algorithm MD5 -ErrorAction Stop).Hash
        if ($sourceHash -ne $destHash) {
            throw "checksum does not match $fileName"
        }

        $timeTaken = ($fileCopyEnd - $fileCopyStart).TotalSeconds
        $speedMBps = if ($timeTaken -gt 0) { ($fileSize / 1MB) / $timeTaken }else{ 0 }
        $roundedSpeedMBps = [math]::Round($speedMBps, 0)
        Write-Host "$targetName Transfer Speed: $roundedSpeedMBps MB/s"
        Write-Host -ForegroundColor Green $filePath "copied and verified. Time:" (New-TimeSpan -Start $fileCopyStart -End $fileCopyEnd) " Speed: " $roundedSpeedMBps "MB/s Size: " ($fileSize / 1MB) "MB"
        return [pscustomobject]@{ Success = $true; Message = $null }
    }
    catch {
        $message = "Could not copy file $fileName to $filePath. $($_.Exception.Message)"
        Write-Host -ForegroundColor Red $message
        return [pscustomobject]@{ Success = $false; Message = $message }
    }
}

function copyFileOfType($inputDir, $file) {
    $dateModified = $file.LastWriteTime
    $parent = $file.Directory.BaseName
    if ([string]::IsNullOrEmpty($parent)) {
        $parent = "other"
    }
    $folderName = Join-Path $outputDir $dateModified.ToString("yyyy") $dateModified.ToString("yyyy-MM-dd") $parent "jpg"
    $filePath = Join-Path $folderName $file.Name
    if ($file.CreationTime.Date -ne $dateModified.Date) {
        Write-Host -ForegroundColor Yellow "File $($file.Name) was modified on $($dateModified.ToString('yyyy-MM-dd'))."
        Write-Host -ForegroundColor Yellow "Moving to modified folder: $folderName"
    }

    $logObj = [pscustomobject]@{
        StartDate = Get-Date
        inputDir = $inputDir
        File = $file.Name
        FileSize = $file.Length
        Source = $file.FullName
        Destination = $filePath
        Success = $false
        Message = $null
        PhotosInProgressDestination = $null
        PhotosInProgressSuccess = $null
        PhotosInProgressMessage = $null
        EndDate = $null
    }
    try {
        $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5 -ErrorAction Stop).Hash
        $copyResult = copyVerifiedFile -file $file -filePath $filePath -sourceHash $sourceHash -targetName "Primary destination"
        $logObj.Success = $copyResult.Success
        $logObj.Message = $copyResult.Message
    }
    catch {
        $logObj.Message = "Could not process file $($file.FullName). $($_.Exception.Message)"
        Write-Host -ForegroundColor Red $logObj.Message
    }
    $logObj.EndDate = Get-Date
    $script:backupLog += $logObj
}

function backupSource($inputDir) {
    $files = @(Get-ChildItem -LiteralPath $inputDir -File -Recurse -Force -ErrorAction Stop | Where-Object {
        $_.Extension -ieq ".jpg" -and -not $_.FullName.StartsWith($destinationPrefix, $pathComparison)
    })

    if (Test-Path -LiteralPath $resumeLogPath) {
        $resumeFiles = @(Import-Csv -LiteralPath $resumeLogPath -ErrorAction Stop | Where-Object { $_.inputDir -eq $inputDir })
        if ($resumeFiles.Count -gt 0) {
            $resumeBackup = Read-Host "Type Resume to continue where last backup failed. Or Enter/Return to continue."
            if ($resumeBackup -eq "Resume") {
                $files = @($files | Where-Object { $_.FullName -in $resumeFiles.Source })
            }
        }
    }

    $fileCount = 0
    foreach ($file in $files) {
        $fileCount++
        Write-Progress -Activity "Progress" -Status "Copying" -PercentComplete (($fileCount / $files.Count) * 100)
        copyFileOfType -inputDir $inputDir -file $file
    }
    Write-Progress -Activity "Progress" -Completed
    $script:backupLog | Where-Object { $_.Success -eq $false } | Export-Csv -LiteralPath $resumeLogPath -NoTypeInformation
}

Write-Host "Backing up $inputDir to $outputDir"
backupSource -inputDir $inputDir
$script:backupLog | Export-Csv -LiteralPath $backupLogPath -Append -NoTypeInformation

$endDate = Get-Date
$fileCount = $script:backupLog.Count
$fileSuccessCount = @($script:backupLog | Where-Object { $_.Success -eq $true }).Count
$fileErrorCount = @($script:backupLog | Where-Object { $_.Success -eq $false }).Count
$fileExistCount = @($script:backupLog | Where-Object { $_.Success -eq $true -and $_.Message -eq "File already exists" }).Count
$newFilesCount = $fileSuccessCount - $fileExistCount
$totalSize = ($script:backupLog | Measure-Object -Property FileSize -Sum).Sum

Write-Host "Script Started: " $date
Write-Host
Write-Host "$inputDir "
Write-Host "Started: " $date
Write-Host "Ended: " $endDate
Write-Host "Total Size: " ($totalSize / 1MB) "MB"
Write-Host "Time taken: " (New-TimeSpan -Start $date -End $endDate)
Write-Host -ForegroundColor Gray "Backup of $inputDir complete."
Write-Host -ForegroundColor Yellow "$fileCount total files in source."
if ($newFilesCount -gt 0) {
    Write-Host -ForegroundColor Green "$newFilesCount new files copied."
}else{
    Write-Host -ForegroundColor Yellow "No new files copied."
}
Write-Host -ForegroundColor Yellow "$fileExistCount files already existed in destination."
Write-Host -ForegroundColor Green "$fileSuccessCount total files successfully backed up."
if ($fileErrorCount -gt 0) {
    Write-Host -ForegroundColor Red "$fileErrorCount files could not be copied."
}
Write-Host "------------------------------------------"
$timeTaken = ($endDate - $date).TotalSeconds
$speedMBps = if ($timeTaken -gt 0) { ($totalSize / 1MB) / $timeTaken }else{ 0 }
Write-Output "Total Transfer Speed: $([math]::Round($speedMBps, 0)) MB/s"
Write-Host "Total Time taken: " (New-TimeSpan -Start $date -End $endDate)