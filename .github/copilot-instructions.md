# Copilot instructions

## Build, test, and lint commands

This repository is a collection of standalone PowerShell scripts. There is no project-level build system, module manifest, Pester suite, or PSScriptAnalyzer configuration.

Use PowerShell's parser as the default validation:

```sh
# Check all tracked .ps1 files
pwsh -NoLogo -NoProfile -Command '$failed=$false; git ls-files "*.ps1" | ForEach-Object { $path=$_; $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) > $null; if ($errors) { Write-Host "PARSE ERRORS: $path" -ForegroundColor Red; $errors | Format-List; $failed=$true } }; if ($failed) { exit 1 }'

# Check one script
pwsh -NoLogo -NoProfile -Command '$path="Backup-SDCard/Backup-SDCard.ps1"; $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) > $null; if ($errors) { $errors | Format-List; exit 1 }'
```

Run scripts directly with `pwsh -NoLogo -NoProfile -File ./path/to/script.ps1 ...` using the script's own parameters. Tenant migration scripts documented in `TenantSwitch/README.md` are run as:

```powershell
.\CopySPsandAppRegs.ps1 -sourceTenant <tenantID> -destTenant <tenantID>
.\Transfer-AZRoles.ps1 -sourceTenant <tenantID> -destTenant <tenantID>
```

## High-level architecture

- The repo is organized as task-focused top-level folders, usually with one primary `.ps1` script per folder. Scripts are independent and procedural; there are no shared modules, dot-sourced helpers, or centralized configuration.
- Media/photo utilities (`Backup-SDCard`, `Resize-Image`, `Check-Video`, `Update-PhotoDates`, `Move-Files`, `Find-FilesInSubFolders`) classify files by extension and date metadata, copy or move into date/type folder structures, and write logs under `~` or the working directory. `Backup-SDCard/Backup-SDCard.ps1` is the largest pipeline and includes cross-platform default paths, checksum verification, resume logging, optional Photos-InProgress mirroring, and date filtering.
- Azure and tenant automation (`Azure Gov`, `AzureDeploy`, `ESU`, `TenantSwitch`, `SCVMM-Arc`) uses Az/AzureAD cmdlets or the Azure CLI to operate against real tenants/subscriptions. These scripts commonly authenticate at runtime and write CSV/log artifacts such as `sourceRoles.csv`, `idLog.csv`, `EnterpriseApplicationReport.csv`, `arcvmm-output.log`, or `importErrors.txt`.
- Windows administration scripts (`StorageSpaces`, `Mount-VHD`, `Disable-USBPowerSave`, `Update-Users`) rely on Windows-only modules/cmdlets such as Storage, WMI, ActiveDirectory, VHD mounting, and elevated/admin execution.
- External tool dependencies are script-specific: `Check-Video` expects `Get-MediaInfo`, `Update-PhotoDates` expects `exiftool.exe`, `Backup-SDCard/DNG-Converter.ps1` expects Adobe DNG Converter paths, and `SCVMM-Arc` installs/uses Azure CLI extensions in a local `.temp` folder.

## Key conventions

- Prefer preserving the standalone script model. Add parameters, helper functions, and validation inside the relevant script/folder instead of introducing repo-wide modules unless explicitly requested.
- Many scripts start with `[CmdletBinding()]` plus a top-level `param` block. Existing public parameter names are often lower camel case (`-inputDirs`, `-outputDir`, `-sourceTenant`); keep those names stable for command-line compatibility.
- Existing scripts frequently use `Write-Host`/`Write-Output` status messages, `try`/`catch` around operations with `-ErrorAction Stop`, and `[pscustomobject]`/`Export-Csv -NoTypeInformation` for logs and reports. Match the local script's style when extending it.
- Preserve current output locations and file schemas unless the task asks to change them. Several scripts exchange data through relative files (`.\Log`, `.\*.csv`, `.temp`) or fixed CSV headers (`ESU/LicenseInfo.csv`).
- Be careful with destructive or environment-changing operations. Storage, Azure, AD, file deletion, and media-move scripts affect real systems; keep existing prompts, confirmations, `-WhatIf`, and default non-destructive paths intact.
- Cross-platform media scripts use `$IsMacOS`, `$IsWindows`, `$IsLinux`, and `$global:separator` with platform-specific defaults (`/Volumes/...`, `S:\...`, `/mnt/...`). Use `Join-Path` or the script's existing separator pattern rather than hard-coding one OS path style.
- `PowerShell_ Resize-Image` is a tracked extensionless copy of the resize function; prefer changing `Resize-Image/Resize-Image.ps1` for runnable script behavior unless the task specifically targets the extensionless file.

## MCP servers

Azure MCP is the relevant MCP server for this repository when working on `Azure Gov`, `AzureDeploy`, `ESU`, `TenantSwitch`, or `SCVMM-Arc`. Use it for read-only discovery of subscriptions, tenants, resource groups, providers, and resource IDs; do not use MCP-driven actions to mutate Azure resources unless the user explicitly asks for that operation.
