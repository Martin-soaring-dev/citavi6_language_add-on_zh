#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Word 加载项目录探测契约(Setup.exe / Install-* 共用语义)。

.DESCRIPTION
    判定:目录存在 + SwissAcademic.Citavi.WordAddIn.dll + 不含 Citavi.exe。
    优先级:显式指定 → 注册表(Word InstallRoot / ClickToRun)→ 约定路径(双 Program Files)
           → StartupSettings6.xml → 文件系统搜索。
    失败返回 $null(调用方应留空跳过),禁止回退到 Citavi bin。
#>

function Test-IsValidWordAddInDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'SwissAcademic.Citavi.WordAddIn.dll'))) { return $false }
    if (Test-Path -LiteralPath (Join-Path $Path 'Citavi.exe')) { return $false }
    return $true
}

function Resolve-WordAddInFromOfficeRoot {
    param([string]$OfficeRoot)
    if ([string]::IsNullOrWhiteSpace($OfficeRoot) -or -not (Test-Path -LiteralPath $OfficeRoot)) { return $null }
    foreach ($rel in @(
            'Root\Office16\ADDINS\Citavi Word AddIn',
            'Office16\ADDINS\Citavi Word AddIn',
            'Root\Office15\ADDINS\Citavi Word AddIn',
            'Office15\ADDINS\Citavi Word AddIn',
            'Root\Office14\ADDINS\Citavi Word AddIn',
            'Office14\ADDINS\Citavi Word AddIn')) {
        $c = Join-Path $OfficeRoot $rel
        if (Test-IsValidWordAddInDir $c) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

function Resolve-WordAddInFromRegistry {
    $views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )
    foreach ($view in $views) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        } catch { continue }
        try {
            foreach ($ver in '16.0', '15.0', '14.0') {
                $k = $base.OpenSubKey("SOFTWARE\Microsoft\Office\$ver\Word\InstallRoot")
                if ($null -eq $k) { continue }
                try {
                    $path = $k.GetValue('Path')
                } finally { $k.Dispose() }
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                $path = $path.TrimEnd('\')
                foreach ($cand in @(
                        (Join-Path $path 'ADDINS\Citavi Word AddIn'),
                        (Join-Path (Split-Path $path -Parent) 'ADDINS\Citavi Word AddIn'),
                        (Join-Path (Split-Path (Split-Path $path -Parent) -Parent) 'ADDINS\Citavi Word AddIn'))) {
                    if (Test-IsValidWordAddInDir $cand) { return (Resolve-Path -LiteralPath $cand).Path }
                }
            }
            foreach ($name in 'PackageFolder', 'InstallPath') {
                $k = $base.OpenSubKey('SOFTWARE\Microsoft\Office\ClickToRun')
                if ($null -eq $k) { break }
                try { $p = $k.GetValue($name) } finally { $k.Dispose() }
                if ([string]::IsNullOrWhiteSpace($p)) { continue }
                $p = $p.TrimEnd('\')
                $hit = Resolve-WordAddInFromOfficeRoot $p
                if ($hit) { return $hit }
                $hit = Resolve-WordAddInFromOfficeRoot (Split-Path $p -Parent)
                if ($hit) { return $hit }
            }
        } finally { $base.Dispose() }
    }
    return $null
}

function Resolve-WordAddInFromStartupSettings {
    $files = @(
        (Join-Path $env:APPDATA 'Swiss Academic Software\StartupSettings6.xml')
    )
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            [xml]$x = Get-Content -LiteralPath $f -Raw
        } catch { continue }
        foreach ($s in @($x.StartupSettings.StartupPathSet)) {
            $af = $s.ApplicationFolder
            if ($af -and (Test-IsValidWordAddInDir $af)) { return (Resolve-Path -LiteralPath $af).Path }
        }
    }
    return $null
}

function Resolve-WordAddInFromFileSystem {
    # 搜索起点列表（不要对已含 Microsoft\Office 的根再拼一层）
    $starts = [System.Collections.Generic.List[string]]::new()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) {
        if (-not $pf) { continue }
        foreach ($sub in @('Microsoft Office', 'Microsoft Office\root')) {
            $p = Join-Path $pf $sub
            if (Test-Path -LiteralPath $p) { $starts.Add($p) }
        }
    }
    $local = Join-Path $env:LOCALAPPDATA 'Microsoft\Office'
    if ($env:LOCALAPPDATA -and (Test-Path -LiteralPath $local)) { $starts.Add($local) }

    foreach ($start in ($starts | Select-Object -Unique)) {
        $hit = Get-ChildItem -LiteralPath $start -Recurse -Filter 'SwissAcademic.Citavi.WordAddIn.dll' -Depth 7 -ErrorAction SilentlyContinue |
            ForEach-Object { $_.DirectoryName } |
            Where-Object { Test-IsValidWordAddInDir $_ } |
            Select-Object -First 1
        if ($hit) { return (Resolve-Path -LiteralPath $hit).Path }
    }
    return $null
}

function Resolve-WordAddInDir {
    param(
        [string]$Override = '',
        [switch]$ThrowOnInvalidOverride
    )
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (Test-IsValidWordAddInDir $Override) { return (Resolve-Path -LiteralPath $Override).Path }
        if ($ThrowOnInvalidOverride) {
            throw "指定的 Word 加载项目录无效(需含 SwissAcademic.Citavi.WordAddIn.dll 且不是 Citavi bin):$Override"
        }
        return $null
    }

    $hit = Resolve-WordAddInFromRegistry
    if ($hit) { return $hit }

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) {
        if (-not $base) { continue }
        $hit = Resolve-WordAddInFromOfficeRoot (Join-Path $base 'Microsoft Office')
        if ($hit) { return $hit }
    }

    $hit = Resolve-WordAddInFromStartupSettings
    if ($hit) { return $hit }

    return Resolve-WordAddInFromFileSystem
}
