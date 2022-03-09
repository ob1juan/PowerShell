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
$global:fileCount = 0
$global:fileSuccessCount = 0
$global:fileErrorCount = 0
$global:rawExts = @(
    ".cr2",
    ".cr3",
    ".arw",
    ".raf",
    ".raw",
    ".rwl"
    ".dng"
)

# Create reusable func for changing dir based on type
function copyFileOfType($file, $type, $parent) {
    # find when it was created
    $dateCreated = $file.CreationTime
    $year = $dateCreated.Year
    $day = (Get-Date -Date $dateCreated).ToString("dd")
    $month = (Get-Date -Date $dateCreated).ToString("MM")

    # Build up a path to where the file should be copied to (e.g. 1_2_Jan) use numbers for ordering and inc month name to make reading easier.
    
    $folderName = $outputDir + "\" + $year + "\" + $year + "-" + $month + "-" + $day + "\" + $parent + "\" `
         + "\" + $type + "\"
	
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
    # If it's not already copied, copy it
    if (-not (Test-Path $filePath)) {
        try {
            Copy-Item $file.FullName -Destination $filePath -ErrorAction Stop
            $global:fileSuccessCount++
        }
        catch {
            $global:fileErrorCount++
            Write-Host -ForegroundColor red "Could not copy file $fileName. $_.Exception.Message"
        }       
    }
}

foreach ($f in $files) { 
    # get the files name
    $fileCount++
    $fileName = $f.Name
    $parent = $f.Directory.BaseName
    $fileExt = [IO.Path]::GetExtension($fileName) 
    Write-Host "File Ext $fileExt"

    if ( [IO.Path]::GetExtension($fileName) -eq '.jpg' ) {
        copyFileOfType -file $f -type "jpg" -parent $parent
        Write-Host "JPG: $f"
    }
    elseif ($global:rawExts -contains $fileExt) {
    #elseif ( [IO.Path]::GetExtension($fileName) -eq '.cr3' -or [IO.Path]::GetExtension($fileName) -eq '.raf') {
        copyFileOfType -file $f -type "raw" -parent $parent
        Write-Host "Raw: $f"
    }
    elseif ($fileExt -eq '.mp4') {
        copyFileOfType -file $f -type "video" -parent $parent
        Write-Host "Video: $f"
    }
    else {
        copyFileOfType -file $f -type "other" -parent $parent
        Write-Host "Other: $f"
    }    
}

Write-Host -ForegroundColor Yellow "$fileCount total files in source."
Write-Host -ForegroundColor Green "$fileSuccessCount files succssfully copied."
if ($fileErrorCount -gt 0) {
    Write-Host -ForegroundColor Red "$fileErrorCount files could not be copied."
}
