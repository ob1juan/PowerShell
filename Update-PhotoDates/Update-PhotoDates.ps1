[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $source=@(),
    [string]
    $csvPath = "exif.json"
)

# Call exiftool to collect all exifdata from a directory, recursively and save it in a file... Important because this process is slow!
try {
    $process = Start-Process -FilePath "exiftool.exe" -ArgumentList "$source -EXT JPG -ISO -ISOSetting -Aperture -ExposureTime -Model -Lens -FocalLength -LensID -ExposureCompensation `
            -MeteringMode -Flash -FocusMode -AFAreaMode -CreateDate -DateTimeOriginal -json > $csvPath" -Wait -RedirectStandardOutput exiftool_output.json -PassThru -NoNewWindow

    $process.WaitForExit()
}
catch {
    Write-Output $_.Exception.Message
    exit
}


# Load the exifdata to a variable for further manipulation
$exif = (get-content $csvPath | ConvertFrom-Json)

# Define a function to change the date of a photo
function Change-Date ($file) {
    
  # Create a new ExifTool object
  $exif = New-Object ExifTool
  # Extract the date taken from the photo metadata
  $dateTaken = $exif.GetTagValue($file, "DateTimeOriginal")
  # Parse the date taken as a DateTime object
  $date = [DateTime]::ParseExact($dateTaken, "yyyy:MM:dd HH:mm:ss", $null)
  # Change the modified and created date of the photo to match the date taken
  (Get-Item $file).LastWriteTime = $date
  (Get-Item $file).CreationTime = $date
}

# Get the directory of photos
$dir = $source
# Loop through each photo in the directory
Get-ChildItem -Path $dir -Filter *.jpg | ForEach-Object {
  # Change the date of the photo
  #Change-Date $_.FullName
}
