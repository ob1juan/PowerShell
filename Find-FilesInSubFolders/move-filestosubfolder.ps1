# Define source and destination root folders
$sourceFolder = "/Volumes/CrucialX104TB/Cleanup/From LRCC"
$destinationRoot = "/Volumes/CrucialX104TB/Cleanup/From LRCC"

# Regex pattern to match yyyy-mm-dd
$datePattern = '\d{4}-\d{2}-\d{2}'

# Loop through each file in the source folder
foreach ($file in Get-ChildItem -Path $sourceFolder -File) {
    if ($file.Name -match $datePattern) {
        $dateString = $Matches[0]
        $year = $dateString.Substring(0, 4)

        # Build destination folder path
        $targetFolder = Join-Path -Path $destinationRoot -ChildPath "$year\$dateString"

        # Create folder if it doesn't exist
        if (-not (Test-Path -Path $targetFolder)) {
            New-Item -Path $targetFolder -ItemType Directory | Out-Null
        }

        # Copy file to target folder
        $destinationPath = Join-Path -Path $targetFolder -ChildPath $file.Name
        Move-Item -Path $file.FullName -Destination $destinationPath

        Write-Host "✅ Copied '$($file.Name)' to '$targetFolder'"
    } else {
        Write-Host "⚠️ Skipped '$($file.Name)' — no date found"
    }
}