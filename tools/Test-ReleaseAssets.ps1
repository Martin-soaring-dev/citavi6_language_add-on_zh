#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate release ZIP/Setup assets and write a SHA-256 manifest.
.DESCRIPTION
    Checks expected versioned filenames, non-empty files, required ZIP entries,
    the seven satellite assemblies, and bundled custom-help RTF files.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+(\.\d+)*([.-][0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$DistDir = Join-Path $RepoDir 'dist'
$ZipPath = Join-Path $DistDir "citavi6-zh-v$Version.zip"
$SetupPath = Join-Path $DistDir "Citavi6-zh-Setup-v$Version.exe"
$ManifestPath = Join-Path $DistDir "SHA256SUMS-v$Version.txt"

foreach ($path in @($ZipPath, $SetupPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required release asset: $path"
    }
    if ((Get-Item -LiteralPath $path).Length -le 0) {
        throw "Release asset is empty: $path"
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $dlls = @($entries | Where-Object { $_ -match '^zh/[^/]+\.dll$' })
    if ($dlls.Count -ne 7) {
        throw "Expected 7 zh satellite assemblies in ZIP; found $($dlls.Count)."
    }

    foreach ($required in @(
        'zh/SwissAcademic.Resources.resources.dll',
        '安装.vbs',
        'Install-Toolkit.ps1',
        'Install-Gui.ps1',
        '使用条款.txt'
    )) {
        if ($entries -notcontains $required) {
            throw "ZIP is missing required entry: $required"
        }
    }

    $helpEntries = @($entries | Where-Object { $_ -match '\.zh\.rtf$' })
    if ($helpEntries.Count -eq 0) {
        throw 'ZIP contains no Chinese custom-help RTF files.'
    }
}
finally {
    $archive.Dispose()
}

$lines = foreach ($path in @($ZipPath, $SetupPath)) {
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash *$([IO.Path]::GetFileName($path))"
}
[IO.File]::WriteAllLines($ManifestPath, [string[]]$lines, [Text.Encoding]::ASCII)

Write-Host "Release asset validation passed for v$Version."
Get-Item -LiteralPath $ZipPath, $SetupPath, $ManifestPath |
    Select-Object Name, Length |
    Format-Table -AutoSize
Get-Content -LiteralPath $ManifestPath
