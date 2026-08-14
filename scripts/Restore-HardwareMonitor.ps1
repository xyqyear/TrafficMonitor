[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'hardware-monitor-dependencies.json'
$destinationRoot = Join-Path $repositoryRoot 'OpenHardwareMonitorApi\.deps'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) "TrafficMonitorDependencies-$([guid]::NewGuid().ToString('N'))"

function Get-VerifiedFile {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Artifact,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $outputDirectory = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Invoke-WebRequest -Uri $Artifact.url -OutFile $OutputPath

    $actualHash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = ([string]$Artifact.sha256).ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 mismatch for $($Artifact.url). Expected $expectedHash, got $actualHash."
    }
}

function Copy-ZipEntry {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)]
        [string]$EntryPath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $entry = $Archive.GetEntry($EntryPath)
    if ($null -eq $entry) {
        throw "Archive entry not found: $EntryPath"
    }

    $outputPath = Join-Path $destinationRoot $DestinationPath
    $outputDirectory = Split-Path -Parent $outputPath
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $inputStream = $entry.Open()
    $outputStream = [System.IO.File]::Open($outputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $inputStream.CopyTo($outputStream)
    }
    finally {
        $outputStream.Dispose()
        $inputStream.Dispose()
    }
}

try {
    if (Test-Path -LiteralPath $destinationRoot) {
        Remove-Item -LiteralPath $destinationRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    foreach ($artifactName in @('libreHardwareMonitor', 'runtimeDependencies')) {
        $artifact = $manifest.PSObject.Properties[$artifactName].Value
        $archivePath = Join-Path $downloadRoot "$artifactName.zip"
        Get-VerifiedFile -Artifact $artifact -OutputPath $archivePath
        $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            foreach ($file in @($artifact.files)) {
                Copy-ZipEntry -Archive $archive -EntryPath $file.source -DestinationPath $file.destination
            }
        }
        finally {
            $archive.Dispose()
        }
    }

    $pawnIoPath = Join-Path $destinationRoot $manifest.pawnIO.destination
    Get-VerifiedFile -Artifact $manifest.pawnIO -OutputPath $pawnIoPath
    Write-Host "Hardware monitor dependencies restored to $destinationRoot"
}
finally {
    if (Test-Path -LiteralPath $downloadRoot) {
        Remove-Item -LiteralPath $downloadRoot -Recurse -Force
    }
}
