<#
.SYNOPSIS
	Imports photos into a target folder.

.DESCRIPTION
	Copies files from one or more source paths into file-type subfolders under a
	target parent folder. Imported files are renamed using the pattern:

		juansphotos-YYYY-MM-DD-originalfilename

	The date is read from photo/video metadata with ExifTool when available and
	falls back to LastWriteTime unless -requireMetadataDate is specified.

.PARAMETER inputPath
	One or more source files or folders to import. Folder sources are scanned
	recursively by default.

.PARAMETER targetFolder
	Required parent import folder. File-type subfolders such as raw, heif, video,
	jpg, and other are created under this folder.

.PARAMETER fileNamePrefix
	Prefix used in imported file names. Defaults to juansphotos.

.PARAMETER addMetadata
	Adds import metadata to imported files. Auto mode embeds metadata in
	friendly formats and writes .xmp sidecars for raw/video/other files.

.EXAMPLE
	./import-photos.ps1 -inputPath /Volumes/CARD/DCIM -targetFolder "/Volumes/Photos-InProgress/Photo Library/In Progress/Juan's Photos/Models/2026/2026-05-09/Anastasiia" -addMetadata
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
param (
	[Parameter(Mandatory=$true)]
	[Alias("source", "inputDirs")]
	[string[]]
	$inputPath,

	[Parameter(Mandatory=$true)]
	[string]
	$targetFolder,

	[string]
	$fileNamePrefix = "juansphotos",

	[switch]
	$addMetadata,

	[ValidateSet("Auto", "Embedded", "Sidecar")]
	[string]
	$metadataMode = "Auto",

	[string[]]
	$metadataKeywords = @(),

	[string]
	$metadataDescription,

	[string]
	$metadataCreator = "Juan's Photos",

	[string]
	$exifToolPath,

	[switch]
	$requireMetadataDate,

	[switch]
	$noRecurse,

	[switch]
	$overwriteExisting,

	[switch]
	$createUniqueNamesForCollisions,

	[string]
	$logPath = "~/Import-Photos-Log.csv"
)

$scriptStarted = Get-Date
$rawExts = @(
	".cr2",
	".cr3",
	".arw",
	".raf",
	".raw",
	".rwl",
	".dng",
	".nef",
	".nrw",
	".orf",
	".rw2",
	".pef",
	".srw",
	".srf",
	".sr2",
	".kdc",
	".dcr",
	".mrw",
	".erf",
	".3fr"
)
$jpgExts = @(
	".jpg",
	".jpeg",
	".jpe",
	".jif",
	".jfif",
	".jfi"
)
$tifExts = @(
	".tif",
	".tiff",
	".psd",
	".psb"
)
$heifExts = @(
	".hif",
	".heif",
	".heic"
)
$imageExts = @(
	".png"
)
$videoExts = @(
	".mov",
	".mp4",
	".wmv",
	".m4v",
	".lrv",
	".avi",
	".mts",
	".m2ts",
	".mpg",
	".mpeg",
	".3gp",
	".3g2",
	".mkv",
	".flv",
	".webm",
	".vob",
	".ogv",
	".ogg",
	".qt",
	".asf",
	".insv",
	".insp"
)
$audioExts = @(
	".mp3",
	".wav",
	".aac"
)
$embeddedMetadataExts = $jpgExts + $tifExts + $heifExts + $imageExts + @(".dng")
$dateTags = @(
	"DateTimeOriginal",
	"CreateDate",
	"MediaCreateDate",
	"TrackCreateDate",
	"CreationDate",
	"FileModifyDate"
)
$importLog = @()

function Get-SafePathSegment {
	param(
		[Parameter(Mandatory=$true)]
		[string]
		$value
	)

	$segment = $value.Trim()
	foreach ($invalidChar in [IO.Path]::GetInvalidFileNameChars()) {
		$segment = $segment.Replace($invalidChar, "-")
	}
	$segment = $segment -replace "[\\/]+", "-"
	$segment = $segment -replace "\s+", " "
	$segment = $segment.Trim(" ", ".", "-")

	if ([string]::IsNullOrWhiteSpace($segment)) {
		throw "'$value' cannot be used as a folder name."
	}

	return $segment
}

function Get-SafeFileNameSegment {
	param(
		[Parameter(Mandatory=$true)]
		[string]
		$value
	)

	$segment = Get-SafePathSegment -value $value
	$segment = $segment -replace "\s+", "-"
	$segment = $segment -replace "-+", "-"
	$segment = $segment.Trim("-")

	if ([string]::IsNullOrWhiteSpace($segment)) {
		throw "'$value' cannot be used as part of a file name."
	}

	return $segment.ToLowerInvariant()
}

function Resolve-ExifToolCommand {
	param([string]$path)

	if (-not [string]::IsNullOrWhiteSpace($path)) {
		if (Test-Path -LiteralPath $path -PathType Leaf) {
			return (Resolve-Path -LiteralPath $path).Path
		}

		$explicitCommand = Get-Command -Name $path -ErrorAction SilentlyContinue
		if ($null -ne $explicitCommand) {
			return $explicitCommand.Source
		}

		throw "Could not find ExifTool at '$path'."
	}

	foreach ($commandName in @("exiftool", "exiftool.exe")) {
		$command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
		if ($null -ne $command) {
			return $command.Source
		}
	}

	return $null
}

function Get-SourceFiles {
	param(
		[Parameter(Mandatory=$true)]
		[string[]]
		$paths,

		[switch]
		$disableRecurse
	)

	$files = @()
	foreach ($path in $paths) {
		if (Test-Path -LiteralPath $path -PathType Container) {
			$getChildItemParams = @{
				LiteralPath = $path
				File = $true
				ErrorAction = "Stop"
			}
			if (-not $disableRecurse) {
				$getChildItemParams.Recurse = $true
			}

			$files += Get-ChildItem @getChildItemParams
		}
		elseif (Test-Path -LiteralPath $path -PathType Leaf) {
			$files += Get-Item -LiteralPath $path -ErrorAction Stop
		}
		else {
			throw "Input path '$path' does not exist."
		}
	}

	return @($files | Sort-Object -Property FullName -Unique)
}

function Get-FileType {
	param([System.IO.FileInfo]$file)

	$extension = $file.Extension.ToLowerInvariant()
	if ($rawExts -contains $extension) { return "raw" }
	if ($jpgExts -contains $extension) { return "jpg" }
	if ($tifExts -contains $extension) { return "tif" }
	if ($heifExts -contains $extension) { return "heif" }
	if ($imageExts -contains $extension) { return "image" }
	if ($videoExts -contains $extension) { return "video" }
	if ($audioExts -contains $extension) { return "audio" }

	return "other"
}

function ConvertFrom-ExifDate {
	param([object]$value)

	if ($null -eq $value) {
		return $null
	}

	$dateText = ([string]$value).Trim()
	if ([string]::IsNullOrWhiteSpace($dateText)) {
		return $null
	}

	if ($dateText -match "^(?<year>\d{4})[:\-](?<month>\d{2})[:\-](?<day>\d{2})[ T](?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})") {
		return [datetime]::new(
			[int]$Matches.year,
			[int]$Matches.month,
			[int]$Matches.day,
			[int]$Matches.hour,
			[int]$Matches.minute,
			[int]$Matches.second
		)
	}

	if ($dateText -match "^(?<year>\d{4})[:\-](?<month>\d{2})[:\-](?<day>\d{2})") {
		return [datetime]::new(
			[int]$Matches.year,
			[int]$Matches.month,
			[int]$Matches.day
		)
	}

	[datetime]$parsedDate = [datetime]::MinValue
	if ([datetime]::TryParse($dateText, [ref]$parsedDate)) {
		return $parsedDate
	}

	return $null
}

function Get-ExifMetadataMap {
	param(
		[Parameter(Mandatory=$true)]
		[System.IO.FileInfo[]]
		$files,

		[string]
		$exifToolCommand
	)

	$metadataMap = @{}
	if ([string]::IsNullOrWhiteSpace($exifToolCommand) -or $files.Count -eq 0) {
		return $metadataMap
	}

	$chunkSize = 100
	for ($startIndex = 0; $startIndex -lt $files.Count; $startIndex += $chunkSize) {
		$endIndex = [Math]::Min($startIndex + $chunkSize - 1, $files.Count - 1)
		$chunk = @($files[$startIndex..$endIndex])
		$arguments = @("-json") + ($dateTags | ForEach-Object { "-$_" }) + ($chunk | ForEach-Object { $_.FullName })

		try {
			$jsonOutput = & $exifToolCommand @arguments 2>$null
			if ($LASTEXITCODE -ne 0 -or $null -eq $jsonOutput) {
				Write-Host -ForegroundColor Yellow "ExifTool could not read metadata for files $($startIndex + 1)-$($endIndex + 1). File dates will be used where allowed."
				continue
			}

			$metadataEntries = @($jsonOutput -join [Environment]::NewLine | ConvertFrom-Json)
			foreach ($metadataEntry in $metadataEntries) {
				if ($null -eq $metadataEntry.SourceFile) {
					continue
				}

				$metadataMap[[string]$metadataEntry.SourceFile] = $metadataEntry
				try {
					$resolvedSourceFile = (Resolve-Path -LiteralPath ([string]$metadataEntry.SourceFile) -ErrorAction Stop).Path
					$metadataMap[$resolvedSourceFile] = $metadataEntry
				}
				catch {
				}
			}
		}
		catch {
			Write-Host -ForegroundColor Yellow "ExifTool metadata read failed for files $($startIndex + 1)-$($endIndex + 1). $($_.Exception.Message)"
		}
	}

	return $metadataMap
}

function Get-TakenDateInfo {
	param(
		[Parameter(Mandatory=$true)]
		[System.IO.FileInfo]
		$file,

		[hashtable]
		$metadataMap
	)

	$metadata = $null
	if ($null -ne $metadataMap -and $metadataMap.ContainsKey($file.FullName)) {
		$metadata = $metadataMap[$file.FullName]
	}

	if ($null -ne $metadata) {
		foreach ($dateTag in $dateTags) {
			if ($metadata.PSObject.Properties.Name -contains $dateTag) {
				$date = ConvertFrom-ExifDate -value $metadata.$dateTag
				if ($null -ne $date) {
					return [pscustomobject]@{
						Date = $date
						Source = $dateTag
					}
				}
			}
		}
	}

	if ($requireMetadataDate) {
		throw "No metadata date was found for $($file.FullName)."
	}

	return [pscustomobject]@{
		Date = $file.LastWriteTime
		Source = "LastWriteTime"
	}
}

function Ensure-Directory {
	param([string]$folderPath)

	if (Test-Path -LiteralPath $folderPath -PathType Container) {
		return
	}

	if ($PSCmdlet.ShouldProcess($folderPath, "Create directory")) {
		New-Item -Path $folderPath -ItemType Directory -ErrorAction Stop | Out-Null
	}
}

function Get-AvailableDestinationPath {
	param(
		[Parameter(Mandatory=$true)]
		[string]
		$folderPath,

		[Parameter(Mandatory=$true)]
		[string]
		$fileName
	)

	$destinationPath = Join-Path -Path $folderPath -ChildPath $fileName
	if ($overwriteExisting -or -not (Test-Path -LiteralPath $destinationPath) -or -not $createUniqueNamesForCollisions) {
		return $destinationPath
	}

	$baseName = [IO.Path]::GetFileNameWithoutExtension($fileName)
	$extension = [IO.Path]::GetExtension($fileName)
	$counter = 1
	do {
		$candidateName = "{0}-{1:d3}{2}" -f $baseName, $counter, $extension
		$destinationPath = Join-Path -Path $folderPath -ChildPath $candidateName
		$counter++
	} while (Test-Path -LiteralPath $destinationPath)

	return $destinationPath
}

function Copy-VerifiedFile {
	param(
		[Parameter(Mandatory=$true)]
		[System.IO.FileInfo]
		$sourceFile,

		[Parameter(Mandatory=$true)]
		[string]
		$destinationPath
	)

	$sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm MD5 -ErrorAction Stop).Hash
	$destinationExists = Test-Path -LiteralPath $destinationPath -PathType Leaf
	if ($destinationExists -and -not $overwriteExisting -and -not $createUniqueNamesForCollisions) {
		$destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm MD5 -ErrorAction Stop).Hash
		if ($sourceHash -eq $destinationHash) {
			return [pscustomobject]@{
				Success = $true
				Message = "Existing file verified"
			}
		}

		return [pscustomobject]@{
			Success = $false
			Message = "Existing file checksum mismatch"
		}
	}

	if (-not $PSCmdlet.ShouldProcess($destinationPath, "Copy $($sourceFile.FullName)")) {
		return [pscustomobject]@{
			Success = $true
			Message = "WhatIf: copy not performed"
		}
	}

	Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force:$overwriteExisting -ErrorAction Stop
	$destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm MD5 -ErrorAction Stop).Hash

	if ($sourceHash -ne $destinationHash) {
		return [pscustomobject]@{
			Success = $false
			Message = "Checksum does not match"
		}
	}

	return [pscustomobject]@{
		Success = $true
		Message = $null
	}
}

function Get-UniqueStrings {
	param([string[]]$values)

	$seen = @{}
	$uniqueValues = @()
	foreach ($value in $values) {
		if ([string]::IsNullOrWhiteSpace($value)) {
			continue
		}

		$cleanValue = $value.Trim()
		$key = $cleanValue.ToLowerInvariant()
		if (-not $seen.ContainsKey($key)) {
			$seen[$key] = $true
			$uniqueValues += $cleanValue
		}
	}

	return $uniqueValues
}

function New-ImportMetadata {
	param(
		[Parameter(Mandatory=$true)]
		[System.IO.FileInfo]
		$sourceFile,

		[Parameter(Mandatory=$true)]
		[string]
		$destinationPath,

		[Parameter(Mandatory=$true)]
		[datetime]
		$takenDate,

		[Parameter(Mandatory=$true)]
		[string]
		$fileType
	)

	$title = [IO.Path]::GetFileNameWithoutExtension($destinationPath)
	$description = $metadataDescription
	if ([string]::IsNullOrWhiteSpace($description)) {
		$description = "Imported on $($takenDate.ToString("yyyy-MM-dd"))."
	}

	$keywords = Get-UniqueStrings -values (@(
		$fileNamePrefix,
		$fileType
	) + $metadataKeywords)

	return [ordered]@{
		Title = $title
		Description = $description
		Creator = $metadataCreator
		Keywords = $keywords
		DateTaken = $takenDate
		ImportedAt = Get-Date
		OriginalFileName = $sourceFile.Name
		ImportedFileName = [IO.Path]::GetFileName($destinationPath)
	}
}

function Write-RdfLanguageAlternative {
	param(
		[System.Xml.XmlWriter]
		$writer,

		[string]
		$rdfNamespace,

		[string]
		$value
	)

	$writer.WriteStartElement("rdf", "Alt", $rdfNamespace)
	$writer.WriteStartElement("rdf", "li", $rdfNamespace)
	$writer.WriteAttributeString("xml", "lang", "http://www.w3.org/XML/1998/namespace", "x-default")
	$writer.WriteString($value)
	$writer.WriteEndElement()
	$writer.WriteEndElement()
}

function Write-RdfList {
	param(
		[System.Xml.XmlWriter]
		$writer,

		[string]
		$rdfNamespace,

		[string]
		$listType,

		[string[]]
		$values
	)

	$writer.WriteStartElement("rdf", $listType, $rdfNamespace)
	foreach ($value in $values) {
		$writer.WriteElementString("rdf", "li", $rdfNamespace, $value)
	}
	$writer.WriteEndElement()
}

function Write-XmpSidecar {
	param(
		[Parameter(Mandatory=$true)]
		[string]
		$destinationPath,

		[Parameter(Mandatory=$true)]
		[System.Collections.IDictionary]
		$metadata
	)

	$sidecarPath = [IO.Path]::ChangeExtension($destinationPath, ".xmp")
	if (-not $PSCmdlet.ShouldProcess($sidecarPath, "Write XMP sidecar metadata")) {
		return [pscustomobject]@{
			Success = $true
			Path = $sidecarPath
			Message = "WhatIf: sidecar not written"
		}
	}

	$settings = [System.Xml.XmlWriterSettings]::new()
	$settings.Indent = $true
	$settings.Encoding = [System.Text.UTF8Encoding]::new($false)

	$rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
	$dcNamespace = "http://purl.org/dc/elements/1.1/"
	$xmpNamespace = "http://ns.adobe.com/xap/1.0/"
	$photoshopNamespace = "http://ns.adobe.com/photoshop/1.0/"
	$writer = [System.Xml.XmlWriter]::Create($sidecarPath, $settings)

	try {
		$writer.WriteStartDocument()
		$writer.WriteStartElement("x", "xmpmeta", "adobe:ns:meta/")
		$writer.WriteStartElement("rdf", "RDF", $rdfNamespace)
		$writer.WriteStartElement("rdf", "Description", $rdfNamespace)
		$writer.WriteAttributeString("rdf", "about", $rdfNamespace, "")
		$writer.WriteAttributeString("xmlns", "dc", $null, $dcNamespace)
		$writer.WriteAttributeString("xmlns", "xmp", $null, $xmpNamespace)
		$writer.WriteAttributeString("xmlns", "photoshop", $null, $photoshopNamespace)

		$writer.WriteStartElement("dc", "title", $dcNamespace)
		Write-RdfLanguageAlternative -writer $writer -rdfNamespace $rdfNamespace -value $metadata.Title
		$writer.WriteEndElement()

		$writer.WriteStartElement("dc", "description", $dcNamespace)
		Write-RdfLanguageAlternative -writer $writer -rdfNamespace $rdfNamespace -value $metadata.Description
		$writer.WriteEndElement()

		$writer.WriteStartElement("dc", "creator", $dcNamespace)
		Write-RdfList -writer $writer -rdfNamespace $rdfNamespace -listType "Seq" -values @($metadata.Creator)
		$writer.WriteEndElement()

		$writer.WriteStartElement("dc", "subject", $dcNamespace)
		Write-RdfList -writer $writer -rdfNamespace $rdfNamespace -listType "Bag" -values $metadata.Keywords
		$writer.WriteEndElement()

		$writer.WriteElementString("xmp", "CreateDate", $xmpNamespace, $metadata.DateTaken.ToString("s"))
		$writer.WriteElementString("xmp", "MetadataDate", $xmpNamespace, $metadata.ImportedAt.ToString("s"))
		$writer.WriteElementString("photoshop", "DateCreated", $photoshopNamespace, $metadata.DateTaken.ToString("yyyy-MM-dd"))

		$writer.WriteEndElement()
		$writer.WriteEndElement()
		$writer.WriteEndElement()
		$writer.WriteEndDocument()
	}
	finally {
		$writer.Close()
	}

	return [pscustomobject]@{
		Success = $true
		Path = $sidecarPath
		Message = $null
	}
}

function Write-EmbeddedMetadata {
	param(
		[Parameter(Mandatory=$true)]
		[string]
		$destinationPath,

		[Parameter(Mandatory=$true)]
		[System.Collections.IDictionary]
		$metadata,

		[Parameter(Mandatory=$true)]
		[string]
		$exifToolCommand
	)

	if (-not $PSCmdlet.ShouldProcess($destinationPath, "Write embedded metadata")) {
		return [pscustomobject]@{
			Success = $true
			Path = $destinationPath
			Message = "WhatIf: embedded metadata not written"
		}
	}

	$arguments = @(
		"-overwrite_original",
		"-sep",
		", ",
		"-XMP-dc:Title=$($metadata.Title)",
		"-XMP-dc:Description=$($metadata.Description)",
		"-XMP-dc:Creator=$($metadata.Creator)",
		"-XMP-dc:Subject=$($metadata.Keywords -join ', ')",
		"-XMP-xmp:CreateDate=$($metadata.DateTaken.ToString("yyyy:MM:dd HH:mm:ss"))",
		"-XMP-xmp:MetadataDate=$($metadata.ImportedAt.ToString("yyyy:MM:dd HH:mm:ss"))",
		"-XMP-photoshop:DateCreated=$($metadata.DateTaken.ToString("yyyy:MM:dd HH:mm:ss"))",
		$destinationPath
	)

	$output = & $exifToolCommand @arguments 2>&1
	if ($LASTEXITCODE -ne 0) {
		return [pscustomobject]@{
			Success = $false
			Path = $destinationPath
			Message = ($output -join " ")
		}
	}

	return [pscustomobject]@{
		Success = $true
		Path = $destinationPath
		Message = $null
	}
}

function Get-ResolvedMetadataMode {
	param(
		[Parameter(Mandatory=$true)]
		[System.IO.FileInfo]
		$file,

		[string]
		$exifToolCommand
	)

	if ($metadataMode -eq "Sidecar") {
		return "Sidecar"
	}

	if ($metadataMode -eq "Embedded") {
		return "Embedded"
	}

	if ([string]::IsNullOrWhiteSpace($exifToolCommand)) {
		return "Sidecar"
	}

	if ($embeddedMetadataExts -contains $file.Extension.ToLowerInvariant()) {
		return "Embedded"
	}

	return "Sidecar"
}

if ([string]::IsNullOrWhiteSpace($targetFolder)) {
	throw "Target folder cannot be empty."
}

Ensure-Directory -folderPath $targetFolder

$prefixFileSegment = Get-SafeFileNameSegment -value $fileNamePrefix
$resolvedExifTool = Resolve-ExifToolCommand -path $exifToolPath

if ($addMetadata -and $metadataMode -eq "Embedded" -and [string]::IsNullOrWhiteSpace($resolvedExifTool)) {
	throw "-metadataMode Embedded requires ExifTool. Install ExifTool or pass -exifToolPath."
}

if ([string]::IsNullOrWhiteSpace($resolvedExifTool)) {
	Write-Host -ForegroundColor Yellow "ExifTool was not found. LastWriteTime will be used for dates where allowed. Auto metadata mode will use XMP sidecars."
}

$files = Get-SourceFiles -paths $inputPath -disableRecurse:$noRecurse
if ($files.Count -eq 0) {
	Write-Host -ForegroundColor Yellow "No files found to import."
	return
}

Write-Host "Importing $($files.Count) file(s) into $targetFolder"
Write-Host "Target folder: $targetFolder"

$metadataMap = Get-ExifMetadataMap -files $files -exifToolCommand $resolvedExifTool
$fileNumber = 0
foreach ($file in $files) {
	$fileNumber++
	$percentComplete = ($fileNumber / $files.Count) * 100
	Write-Progress -Activity "Importing photos" -Status $file.Name -PercentComplete $percentComplete

	$logItem = [ordered]@{
		StartDate = Get-Date
		Source = $file.FullName
		Destination = $null
		TargetFolder = $targetFolder
		DateTaken = $null
		DateSource = $null
		FileType = $null
		OriginalFileName = $file.Name
		ImportedFileName = $null
		FileSize = $file.Length
		CopySuccess = $false
		CopyMessage = $null
		MetadataMode = $null
		MetadataPath = $null
		MetadataSuccess = $null
		MetadataMessage = $null
		EndDate = $null
	}

	try {
		$takenDateInfo = Get-TakenDateInfo -file $file -metadataMap $metadataMap
		$takenDate = $takenDateInfo.Date
		$fileType = Get-FileType -file $file
		$dateFolder = $takenDate.ToString("yyyy-MM-dd")
		$destinationFolder = Join-Path -Path $targetFolder -ChildPath $fileType
		$importedFileName = "{0}-{1}-{2}" -f $prefixFileSegment, $dateFolder, $file.Name
		$destinationPath = Get-AvailableDestinationPath -folderPath $destinationFolder -fileName $importedFileName

		$logItem.DateTaken = $takenDate
		$logItem.DateSource = $takenDateInfo.Source
		$logItem.FileType = $fileType
		$logItem.Destination = $destinationPath
		$logItem.ImportedFileName = [IO.Path]::GetFileName($destinationPath)

		Ensure-Directory -folderPath $destinationFolder
		$copyResult = Copy-VerifiedFile -sourceFile $file -destinationPath $destinationPath
		$logItem.CopySuccess = $copyResult.Success
		$logItem.CopyMessage = $copyResult.Message

		if (-not $copyResult.Success) {
			Write-Host -ForegroundColor Red "Could not import $($file.FullName). $($copyResult.Message)"
			continue
		}

		if ($copyResult.Message -eq "Existing file verified") {
			Write-Host -ForegroundColor DarkGreen "Skipped existing verified file -> $destinationPath"
			continue
		}

		if ($addMetadata) {
			$resolvedMode = Get-ResolvedMetadataMode -file $file -exifToolCommand $resolvedExifTool
			$metadata = New-ImportMetadata -sourceFile $file -destinationPath $destinationPath -takenDate $takenDate -fileType $fileType
			$metadataResult = $null

			if ($resolvedMode -eq "Embedded") {
				$metadataResult = Write-EmbeddedMetadata -destinationPath $destinationPath -metadata $metadata -exifToolCommand $resolvedExifTool
			}
			else {
				$metadataResult = Write-XmpSidecar -destinationPath $destinationPath -metadata $metadata
			}

			$logItem.MetadataMode = $resolvedMode
			$logItem.MetadataPath = $metadataResult.Path
			$logItem.MetadataSuccess = $metadataResult.Success
			$logItem.MetadataMessage = $metadataResult.Message

			if (-not $metadataResult.Success) {
				Write-Host -ForegroundColor Yellow "Imported $($file.Name), but metadata failed. $($metadataResult.Message)"
			}
		}

		Write-Host -ForegroundColor Green "Imported $($file.Name) -> $destinationPath"
	}
	catch {
		$logItem.CopySuccess = $false
		$logItem.CopyMessage = $_.Exception.Message
		Write-Host -ForegroundColor Red "Could not import $($file.FullName). $($_.Exception.Message)"
	}
	finally {
		$logItem.EndDate = Get-Date
		$importLog += [pscustomobject]$logItem
	}
}

Write-Progress -Activity "Importing photos" -Completed

if ($importLog.Count -gt 0) {
	$resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($logPath)
	$logFolder = Split-Path -Path $resolvedLogPath -Parent
	if (-not [string]::IsNullOrWhiteSpace($logFolder)) {
		Ensure-Directory -folderPath $logFolder
	}
	$importLog | Export-Csv -Path $resolvedLogPath -Append -NoTypeInformation
}

$copiedFiles = @($importLog | Where-Object { $_.CopySuccess -eq $true -and [string]::IsNullOrWhiteSpace($_.CopyMessage) })
$skippedExistingFiles = @($importLog | Where-Object { $_.CopySuccess -eq $true -and $_.CopyMessage -eq "Existing file verified" })
$existingMismatchFiles = @($importLog | Where-Object { $_.CopySuccess -eq $false -and $_.CopyMessage -eq "Existing file checksum mismatch" })
$failedCopies = @($importLog | Where-Object { $_.CopySuccess -eq $false }).Count
$metadataFailures = @($importLog | Where-Object { $_.MetadataSuccess -eq $false }).Count
$elapsed = New-TimeSpan -Start $scriptStarted -End (Get-Date)

Write-Host "------------------------------------------"
Write-Host "Import complete."
Write-Host -ForegroundColor Green "$($copiedFiles.Count) file(s) copied."
if ($skippedExistingFiles.Count -gt 0) {
	Write-Host -ForegroundColor DarkGreen "$($skippedExistingFiles.Count) existing file(s) verified and skipped."
}
if ($failedCopies -gt 0) {
	Write-Host -ForegroundColor Red "$failedCopies file(s) failed."
}
if ($existingMismatchFiles.Count -gt 0) {
	Write-Host -ForegroundColor Red "$($existingMismatchFiles.Count) existing file(s) did not match source:"
	foreach ($existingMismatchFile in $existingMismatchFiles) {
		Write-Host -ForegroundColor Red "Source: $($existingMismatchFile.Source)"
		Write-Host -ForegroundColor Red "Destination: $($existingMismatchFile.Destination)"
	}
}
if ($metadataFailures -gt 0) {
	Write-Host -ForegroundColor Yellow "$metadataFailures file(s) imported with metadata errors."
}
Write-Host "Log: $logPath"
Write-Host "Time taken: $elapsed"
