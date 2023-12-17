# Check if the number of arguments is correct
if ($args.Length -ne 2) {
    Write-Host "Usage: $PSCommandPath <source_folder> <destination_folder>"
    exit 1
}

# Check if the directories exist
if (-not (Test-Path $args[0] -PathType Container)) {
    Write-Host "Directory $($args[0]) does not exist"
    exit 1
}

if (-not (Test-Path $args[1] -PathType Container)) {
    Write-Host "Directory $($args[1]) does not exist"
    exit 1
}

# Find the missing files in the destination folder
$source_files = Get-ChildItem $args[0] -Recurse | Select-Object FullName -ExpandProperty FullName
$destination_files = Get-ChildItem $args[1] -Recurse | Select-Object FullName -ExpandProperty FullName

Compare-Object $source_files $destination_files | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object InputObject
