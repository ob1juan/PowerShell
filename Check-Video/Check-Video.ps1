[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $inputDir
)

# Check if the folder exists, if it doesn't create it
$badFolder = "$inputDir\bad"

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
  $mediaInfo = Get-MediaInfo $file
  $format = $mediaInfo.Format
  $duration = $mediaInfo.Duration
  
  # Check if the video format is valid
  if ($format -ne "") {
    # Print the video information
    Write-Output "Video file: $file"
    Write-Output "Format: $format"
    Write-Output "Duration: $duration seconds"
    # Return True if the video file is playable
    return $true
  }
  else {
    # Print an error message
    Write-Output "Error: Cannot open video file $file"
    # Return False if the video file is not playable
    return $false
  }
}

foreach ($file in $files) {
    $result = Check-Video $file
    if (-not $result) {
        Write-Host -ForegroundColor red "Moving $file to $badFolder"
        Move-Item $file $badFolder
    }
}
