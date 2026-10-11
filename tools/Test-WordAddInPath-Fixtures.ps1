#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deterministic fixture tests for the Word add-in path contract.
.DESCRIPTION
    Uses temporary directories and does not depend on Office, registry keys,
    StartupSettings6.xml, or a particular Windows installation layout.
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoDir 'tools\lib\Resolve-WordAddInPath.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ("citavi-word-path-test-" + [guid]::NewGuid().ToString('N'))
$valid = Join-Path $root 'Office\ADDINS\Citavi Word AddIn'
$missingDll = Join-Path $root 'missing-dll'
$citaviBin = Join-Path $root 'Citavi 6\bin'
New-Item -ItemType Directory -Force -Path $valid, $missingDll, $citaviBin | Out-Null

$fail = 0
function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Host "PASS $name" }
    else { Write-Host "FAIL $name"; $script:fail++ }
}

try {
    Set-Content -LiteralPath (Join-Path $valid 'SwissAcademic.Citavi.WordAddIn.dll') -Value 'fixture'
    Set-Content -LiteralPath (Join-Path $missingDll 'Citavi.exe') -Value 'fixture'
    Set-Content -LiteralPath (Join-Path $citaviBin 'Citavi.exe') -Value 'fixture'
    Set-Content -LiteralPath (Join-Path $citaviBin 'SwissAcademic.Citavi.WordAddIn.dll') -Value 'fixture'

    Check 'valid add-in directory accepted' (Test-IsValidWordAddInDir $valid)
    Check 'directory without add-in DLL rejected' (-not (Test-IsValidWordAddInDir $missingDll))
    Check 'Citavi bin rejected even if add-in DLL exists' (-not (Test-IsValidWordAddInDir $citaviBin))
    Check 'valid explicit override resolves' ((Resolve-WordAddInDir -Override $valid) -eq (Resolve-Path -LiteralPath $valid).Path)
    Check 'invalid explicit override returns null' ($null -eq (Resolve-WordAddInDir -Override $missingDll))
    $threw = $false
    try { $null = Resolve-WordAddInDir -Override $missingDll -ThrowOnInvalidOverride }
    catch { $threw = $true }
    Check 'invalid explicit override can throw on request' $threw

    Write-Host "Fixture test failures: $fail"
    if ($fail -gt 0) { exit 1 }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
