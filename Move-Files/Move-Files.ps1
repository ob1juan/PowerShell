[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $inputDir,
    [Parameter(Mandatory=$true)]
    [string]
    $search
)

$files = Get-ChildItem $inputDir -file -Recurse
$global:OS
$global:separator
$global:rawFolders = @()
$global:fileCount = 0
$global:fileSuccessCount = 0
$global:fileErrorCount = 0

if ($IsMacOS){
    Write-Host "MacOS"
    $OS = "MacOS"
    $global:separator = "/"
}elseif ($IsWindows){
    Write-Host "Windows"
    $OS = "Windows"
    $global:separator = "\"
}elseif ($IsLinux){
    Write-Host "Linux"
    $OS = "Linux"
    $global:separator = "/"
}else{
    Write-Host "What is this running on?"
}

function moveFile($file) {
    # find when it was created
    $dateCreated = $file.CreationTime
    $year = $dateCreated.Year
    $day = (Get-Date -Date $dateCreated).ToString("dd")
    $month = (Get-Date -Date $dateCreated).ToString("MM")

    # Build up a path to where the file should be copied to (e.g. 1_2_Jan) use numbers for ordering and inc month name to make reading easier.
    $dest = $file.directory.FullName
    $fileName = $file.name
    $searchLength = $search.Length
    $folderName = $file.name.SubString($searchLength,10)
    $destPath = $dest + "/" + $folderName

    # Check if the folder exists, if it doesn't create it
    if (-not (Test-Path $destPath)) { 
        try {
            new-item $destPath -itemtype directory -ErrorAction Stop
        }
        catch {
            Write-Host -ForegroundColor red "Could not create $destPath. $_.Exception.Message" 
        }
    }
    

    $filePath = $destPath + $global:separator + $fileName

    # If it's not already copied, copy it
    if (-not (Test-Path $filePath)) {
        try {
            Move-Item $file.FullName -Destination $destPath -ErrorAction Stop
            Write-Host -ForegroundColor Green "$filePath"
            $global:fileSuccessCount++
        }
        catch {
            $global:fileErrorCount++
            Write-Host -ForegroundColor red "Could not move file $fileName. $_.Exception.Message"
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

    moveFile -file $f
}

$date = Get-Date
Write-host $date
Write-Host -ForegroundColor Yellow "$fileCount total files in source."
Write-Host -ForegroundColor Green "$fileSuccessCount files succssfully copied."
if ($fileErrorCount -gt 0) {
    Write-Host -ForegroundColor Red "$fileErrorCount files could not be copied."
}