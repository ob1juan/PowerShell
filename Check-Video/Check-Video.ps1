[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $inputDir,
    [Parameter(Mandatory=$true)]
    [string[]]
    $outputDir
)

# Check if the folder exists, if it doesn't create it
$badFolder = "$outputDir"

$videoExts = @(
    ".mov",
    ".mp4",
    ".wmv",
    ".m4v",
    ".lrv"
)

$files = Get-ChildItem -Path $inputDir -File | Where-Object { $videoExts -contains $_.Extension }

if (-not (Test-Path $badFolder)) { 
    try {
        new-item $badFolder -itemtype directory -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor red "Could not create $badFolder. $_.Exception.Message" 
    }
}

# Define a function to check the video file
function Check-Video ($file) {
  # Create a new MediaInfo object
  $mediaInfo = Get-MediaInfo $file.FullName
  $format = $mediaInfo.Format
  $duration = $mediaInfo.Duration

  # Check if the video format is valid
  if ($format -ne "") {
    # Print the video information
    Write-Output "Video file: $file"
    #Write-Output "Format: $format"
    #Write-Output "Duration: $duration seconds"
    # Return True if the video file is playable
    return $true
  }
  else {
    # Print an error message
    Write-Output "Error: Cannot open video file $file"
    Write-Host -ForegroundColor Yellow "Moving $file to $badFolder"
    try {
        Move-Item $file.FullName $badFolder -ErrorAction Stop
        Write-Output "Moved $file to $badFolder"
    }
    catch {
        Write-Host -ForegroundColor red "Could not move $file to $badFolder. $_.Exception.Message"
    }
   
    # Return False if the video file is not playable
    return $false
  }
}

foreach ($file in $files) {
    Check-Video $file
}
