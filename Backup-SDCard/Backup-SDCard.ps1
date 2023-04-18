[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $inputDir,
    [Parameter(Mandatory=$true)]
    [string]
    $outputDir
)

# get all files inside all folders and sub folders
$files = Get-ChildItem $inputDir -file -Recurse
$global:OS
$global:separator
$global:dngConverter
$global:rawFolders = @()
$global:fileCount = 0
$global:rawFileCount = 0
$global:crawFileCount = 0
$global:fileSuccessCount = 0
$global:fileErrorCount = 0
$global:filesNotCopied = @()
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
        $global:crawFileCount ++
    }
    catch {
        $global:fileErrorCount++
        Write-Host -ForegroundColor red "Could not compress $fileName. $_.Exception.Message"
    }
}

function copyFileOfType($file, $type, $parent) {
    # find when it was created
    $dateCreated = $file.CreationTime
    $year = $dateCreated.Year
    $day = (Get-Date -Date $dateCreated).ToString("dd")
    $month = (Get-Date -Date $dateCreated).ToString("MM")
    $fileName = $file.Name

    # Build up a path to where the file should be copied to (e.g. 1_2_Jan) use numbers for ordering and inc month name to make reading easier.
    
    $folderName = $outputDir + $global:separator + $year + $global:separator + $year + "-" + $month + "-" + $day + $global:separator + $parent + $global:separator `
         + $type + $global:separator
	
    if ($type -eq "profile"){
        $folderName = $outputDir + $global:separator + "Profiles" + $global:separator + $year + $global:separator + $year + "-" + $month + "-" + $day + $global:separator + $parent + $global:separator
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

    if ((-not (Test-Path $filePath)) -or ($sourceHash -ne $destHash)) {
        try {
            Write-Host -ForegroundColor Yellow "sourceHash $sourceHash / destHash $destHash"
            Copy-Item $file.FullName -Destination $filePath -ErrorAction Stop
            Write-Host -ForegroundColor Green "$fileName"
            $destHash = (get-filehash $filePath -Algorithm md5).Hash
            if ($sourceHash -eq $destHash){
                Write-Host -ForegroundColor Green $filePath "matches checksum."
                $global:fileSuccessCount++
            }else{
                $global:fileErrorCount++
                Write-Host -ForegroundColor red "checksum does not match $fileName. $_.Exception.Message"
            }
        }
        catch {
            $global:fileErrorCount++
            $global:filesNotCopied += $filePath
            Write-Host -ForegroundColor red "Could not copy file $fileName. $_.Exception.Message"
        }    
    }

    if ($type -eq "raw"){
        if($global:rawFolders -notcontains $folderName){
            $global:rawFolders += $folderName
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
        $global:rawFileCount ++
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

foreach ($rawFolder in $global:rawFolders){
    $outFolderName = $rawFolder -replace ("raw", "rawc")
    #compressDNG -folderName $rawFolder -outFolderName $outFolderName
}


$date = Get-Date
Write-host $date
Write-Host -ForegroundColor Yellow "$fileCount total files in source."
Write-Host -ForegroundColor Green "$fileSuccessCount files succssfully copied."
if ($fileErrorCount -gt 0) {
    Write-Host -ForegroundColor Red "$global:fileErrorCount files could not be copied."
    Write-Host -ForegroundColor Red "Files not copied:"
    foreach ($file in $global:filesNotCopied){
        Write-Host -ForegroundColor Red $file
    }
}

if ($fileSuccessCount -gt $fileErrorCount){
    $inputDir = $inputDir -replace(':','')
    $format = Read-Host "Type FORMAT to format the $inputDir."
    if ($format -ceq "FORMAT"){
        $label = (Get-Volume -DriveLetter $inputDir).FileSystemLabel
        Format-Volume -DriveLetter $inputDir -NewFileSystemLabel $label
    }
}

