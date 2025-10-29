# Define source and destination folders
$sourceFolder = "/Volumes/CrucialX104TB/Cleanup/LRCC 07 2023"
$destinationFolder = "/Volumes/CrucialX104TB/Cleanup/From LRCC"

# Get all filenames in destination folder (recursively)
$existingDestFileNames = Get-ChildItem -Path $destinationFolder -Recurse -File | Select-Object -ExpandProperty Name

# Prepare list to track copied files
$copiedFiles = @()

# Loop through each file in the source folder
foreach ($sourceFile in Get-ChildItem -Path $sourceFolder -File) {
    if ($existingDestFileNames -notcontains $sourceFile.Name) {
        # File not found in destination tree, copy it to root of destination
        $targetPath = Join-Path -Path $destinationFolder -ChildPath $sourceFile.Name
        Copy-Item -Path $sourceFile.FullName -Destination $targetPath
        $copiedFiles += $sourceFile.Name
    }
}

# Output report
if ($copiedFiles.Count -gt 0) {
    Write-Host "`n✅ Files copied:"
    $copiedFiles | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "`n📁 All source files already exist somewhere in the destination folder tree. No files were copied."
}