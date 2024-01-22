[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $source=@(),
    [string]
    $destination,
    [int]
    $batchSize = 1000,
    [int]
    $breakTime = 30
)

$files = Get-ChildItem -Path $source -File

# Loop through the files in batches
for ($i = 0; $i -lt $files.Count; $i += $batchSize) {
  # Get the current batch of files
  $batch = $files[$i..($i + $batchSize - 1)]
  # Copy the batch of files to the destination directory
  Copy-Item -Path $batch.FullName -Destination $destination
  # Write a message to indicate the progress
  Write-Host "Copied $batchSize files from $source to $destination"
  # Wait for the break time
  Start-Sleep -Seconds $breakTime
}
