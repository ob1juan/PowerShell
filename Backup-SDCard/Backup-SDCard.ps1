[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $inputDirs=@(),
    [string]
    $outputDir = "B:\Backup\CardBackup",
    [bool]
    $format = $false
)

$global:OS
$global:separator
$global:dngConverter
$global:rawExts = @(
    ".cr2",
    ".cr3",
    ".arw",
    ".raf",
    ".raw",
    ".rwl"
    ".dng"
)
$global:videoExts = @(
    ".mov",
    ".mp4",
    ".wmv",
    ".m4v",
    ".lrv"
)
$global:tifExts =@(
    ".tif",
    ".tiff",
    ".psd",
    ".psb"
)
$global:heifExts =@(
    ".hif",
    ".heif"
)
$global:audioExts = @(
    ".mp3",
    ".wav",
    ".aac"
)
$global:profileExts = @(
    ".lcs"
)

if ($IsMacOS){
    #Write-Host "MacOS"
    $global:OS = "MacOS"
    $global:separator = "/"
    $global:dngConverter = "open -a '/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter' --args -c"
}elseif ($IsWindows){
    #Write-Host "Windows"
    $global:OS = "Windows"
    $global:separator = "\"
    $global:dngConverter = "'C:\Program Files\Adobe DNG Converter.exe' -c"
}elseif ($IsLinux){
    #Write-Host "Linux"
    $global:OS = "Linux"
    $global:separator = "/"
}else{
    Write-Host "What is this running on?"
}
$global:resumeLogPath = "~/Backup-SDCard-Resume.log"
$global:backupLog = @()
$global:backupLogPath = "~/Backup-SDCard-Log.log"

function copyFileOfType($file, $type, $parent) {
    # find when it was created
    $dateCreated = $file.CreationTime
    $year = $dateCreated.Year
    $day = (Get-Date -Date $dateCreated).ToString("dd")
    $month = (Get-Date -Date $dateCreated).ToString("MM")
    $fileName = $file.Name

    # Build up a path to where the file should be copied to (e.g. 1_2_Jan) use numbers for ordering and inc month name to make reading easier.
    if ($null -eq $parent){
        $parent = "root"
    }
    $folderName = $outputDir + $global:separator + $year + $global:separator + $year + "-" + $month + "-" + $day + $global:separator + $parent + $global:separator `
         + $type + $global:separator
	
    if ($type -eq "profile"){
        $folderName = $outputDir + $global:separator + "Profiles" + $global:separator + $year + $global:separator + $year + "-" + $month + "-" + $day + $global:separator
    }

    # Check if the folder exists, if it doesn't create it
    if (-not (Test-Path $folderName)) { 
        try {
            new-item $folderName -itemtype directory -ErrorAction Stop
        }
        catch {
            Write-Host -ForegroundColor red "Could not create $folderName. $_.Exception.Message" 
        }
    }
    # build up the full path inc filename
    $filePath = $folderName + $fileName
    #Write-host -ForegroundColor DarkCyan $parent
    #Write-Host -ForegroundColor Cyan $filePath

    # If it's not already copied, copy it
    $sourceHash = (get-filehash $file.FullName -Algorithm md5).Hash
    $destHash = (get-filehash $filePath -Algorithm md5 -ErrorAction SilentlyContinue).Hash

    $logObj = New-Object psobject
    $logObj | Add-Member -MemberType NoteProperty -Name "inputDir" -Value $inputDir
    $logObj | Add-Member -MemberType NoteProperty -Name "File" -Value $fileName
    $logObj | Add-Member -MemberType NoteProperty -Name "Source" -Value $file.FullName
    $logObj | Add-Member -MemberType NoteProperty -Name "Destination" -Value $filePath
    $logObj | Add-Member -MemberType NoteProperty -Name "Success" -Value $fileSuccess
    $logObj | Add-Member -MemberType NoteProperty -Name "Message" -Value $fileError

    if ((-not (Test-Path $filePath)) -or ($sourceHash -ne $destHash)) {
        try {
            #Write-Host -ForegroundColor Yellow "sourceHash $sourceHash / destHash $destHash"
            Copy-Item $file.FullName -Destination $filePath -ErrorAction Stop
            #Write-Host -ForegroundColor Green "$fileName"
            $destHash = (get-filehash $filePath -Algorithm md5).Hash
            if ($sourceHash -eq $destHash){
                Write-Host -ForegroundColor Green $filePath "copied and verified."
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
    $global:backupLog += $logObj
}

function backupSource($inputDir){
    # get all files inside all folders and sub folders
    $files = Get-ChildItem $inputDir -file -Recurse

    $sourceVolume = Get-Volume (($inputDir) -split ":")[0]
    $sourceDriveLetter = (Get-Volume (($inputDir) -split ":")[0]).DriveLetter
    $rawFolders = @()
    $fileCount = 0
    $rawFileCount = 0
    $crawFileCount = 0
    
    # Create reusable func for changing dir based on type
    function compressDNG($folderName, $outFolderName) {
        write-host "compressing DNG $folderName"
        $rawFiles = Get-ChildItem $folderName -file -Recurse

        if (-not (Test-Path $outFolderName)) { 
            try {
                new-item $outFolderName -itemtype directory -ErrorAction Stop
                Write-Host "Created Folder $outFolderName"
            }
            catch {
                Write-Host -ForegroundColor red "Could not create $outFolderName. $_.Exception.Message" 
            }
        }

        $doDngConverter = $global:dngConverter + " -d '$outFolderName'"

        foreach ($rawFile in $rawFiles){
            $filePath = $rawFile.FullName
            $doDngConverter += " '$filePath'"
        }
        
        Write-Host "dngConverter = $doDngConverter"
        try {
            Invoke-Expression $doDngConverter
            $crawFileCount ++
        }
        catch {
            $fileErrorCount++
            Write-Host -ForegroundColor red "Could not compress $fileName. $_.Exception.Message"
        }
    }

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
            copyFileOfType -file $f -type "jpg" -parent $parent
            #Write-Host "JPG: $f"
        }
        elseIf($global:heifExts -contains $fileExt){
            copyFileOfType -file $f -type "heif" -parent $parent
        }
        elseif ($global:rawExts -contains $fileExt) {
        #elseif ( [IO.Path]::GetExtension($fileName) -eq '.cr3' -or [IO.Path]::GetExtension($fileName) -eq '.raf') {
            copyFileOfType -file $f -type "raw" -parent $parent
            $rawFileCount ++
            #Write-Host "Raw: $f"
        }
        elseif ($global:videoExts -contains $fileExt) {
            copyFileOfType -file $f -type "video" -parent $parent
            #Write-Host "Video: $f"
        }
        elseif ($global:profileExts -contains $fileExt){
            copyFileOfType -file $f -type "profile" -parent $parent
            #Write-Host "Profile: $f"
        }
        elseif ($global:audioExts -contains $fileExt){
            copyFileOfType -file $f -type "audio" -parent $parent
            #Write-Host "Profile: $f"
        }
        else {
            copyFileOfType -file $f -type "other" -parent $parent
            #Write-Host "Other: $f"
        }    
    }

    foreach ($rawFolder in $rawFolders){
        $outFolderName = $rawFolder -replace ("raw", "rawc")
        #compressDNG -folderName $rawFolder -outFolderName $outFolderName
    }
         
    if ($fileSuccessCount -gt 0 -AND $fileErrorCount -eq 0 -AND $format -eq $true){
        $format = Read-Host "Type FORMAT to format the $sourceDriveLetter."
        if ($format -ceq "FORMAT"){
            $label = (Get-Volume -DriveLetter $sourceDriveLetter).FileSystemLabel
            Format-Volume -DriveLetter $sourceDriveLetter -NewFileSystemLabel $label
        }
    } 

    $filesNotCopied = $global:backupLog | Where-Object {$_.Success -eq $false}
    $filesNotCopied |Export-Csv -Path "~/Backup-SDCard-Resume.log" -NoTypeInformation
}

foreach ($inputDir in $inputDirs){
    write-host "Backing up $inputDir"
    backupSource -inputDir $inputDir
}

$global:backupLog | Export-Csv -Path $global:backupLogPath -Append -NoTypeInformation
$date = Get-Date
Write-host $date

foreach ($inputDir in $inputDirs){
    $log = $global:backupLog |Where-Object {$_.inputDir -eq $inputDir}
    $fileCount = $log |Where-Object {$_.inputDir -eq $inputDir} | Measure-Object | Select-Object -ExpandProperty Count
    $fileSuccessCount = $log | Where-Object {$_.Success -eq $true} | Measure-Object | Select-Object -ExpandProperty Count
    $fileErrorCount = $log | Where-Object {$_.Success -eq $false} | Measure-Object | Select-Object -ExpandProperty Count
    
    Write-Host -ForegroundColor Gray "Backup of $inputDir complete."
    Write-Host -ForegroundColor Yellow "$fileCount total files in source."
    Write-Host -ForegroundColor Green "$fileSuccessCount files succssfully copied."
    Write-Host "------------------------------------------"
    
    if ($fileErrorCount -gt 0) {
        Write-Host -ForegroundColor Red "$fileErrorCount files could not be copied."
        <#
        Write-Host -ForegroundColor Red "Files not copied:"
        foreach ($file in $filesNotCopied){
            Write-Host -ForegroundColor Red $file
        }
        #>
    }
}


