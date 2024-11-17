# Define source and target folders
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $sourceFolder,
    [Parameter(Mandatory=$true)]
    [string]
    $targetFolder
)

# Get list of files in both folders
$sourceFiles = Get-ChildItem -Path $sourceFolder
$targetFiles = Get-ChildItem -Path $targetFolder

# Compare file lists and delete extra files from target folder
foreach ($targetFile in $targetFiles) {
    $sourceFile = $sourceFiles | Where-Object { $_.Name -eq $targetFile.Name }
    if (-not $sourceFile) {
        Remove-Item -Path $targetFile.FullName -Force
        Write-Output "Deleted $($targetFile.FullName)"
    }
}
