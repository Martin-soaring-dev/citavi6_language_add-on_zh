#!/usr/bin/env pwsh
<#
.SYNOPSIS
    用 Inno Setup 把语言包 + 快速帮助打包成单文件安装程序(Setup.exe)。
.DESCRIPTION
    依赖 Inno Setup 6/7 的 ISCC.exe(可用 winget install JRSoftware.InnoSetup 安装)。
    产物: dist/Citavi6-zh-Setup-v<版本>.exe
.EXAMPLE
    pwsh ./tools/Build-Installer.ps1 -Version 0.102
#>
[CmdletBinding()]
param(
    [string]$Version = '0.102',
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$Repo   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Iss    = Join-Path $PSScriptRoot 'installer\Citavi6-zh.iss'
$ZhDir  = Join-Path $Repo 'dist\zh'
$HelpDir= Join-Path $Repo 'custom-help'

function Find-Iscc {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe')
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

if (-not (Test-Path $Iss)) { throw "找不到 Inno 脚本: $Iss" }

# 1) 确保语言包构建产物存在
if (-not $SkipBuild -or -not (Test-Path (Join-Path $ZhDir 'SwissAcademic.Resources.resources.dll'))) {
    Write-Host '== 构建语言包 ==' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'Build-LanguagePack.ps1')
}
if (-not (Test-Path (Join-Path $ZhDir 'SwissAcademic.Resources.resources.dll'))) { throw "语言包不完整: $ZhDir" }
if (-not (Test-Path $HelpDir)) { throw "找不到快速帮助目录: $HelpDir" }

$dllCount  = @(Get-ChildItem $ZhDir  -Filter *.dll).Count
$helpCount = @(Get-ChildItem $HelpDir -Filter *.zh.rtf).Count
Write-Host ("语言包 DLL: {0} 个;快速帮助: {1} 个" -f $dllCount, $helpCount)

# 2) 定位 ISCC
$iscc = Find-Iscc
if (-not $iscc) {
    throw "未找到 Inno Setup 编译器 ISCC.exe。请先安装:winget install JRSoftware.InnoSetup"
}
Write-Host "ISCC: $iscc"

# 3) 编译
$out = Join-Path $Repo "dist\Citavi6-zh-Setup-v$Version.exe"
if (Test-Path $out) { Remove-Item $out -Force }

$args = @("/DRepoRoot=$Repo", "/DAppVersion=$Version", "/Qp", $Iss)
Write-Host "== ISCC 编译 ==" -ForegroundColor Cyan
& $iscc @args
$code = $LASTEXITCODE
if ($code -ne 0) { throw "ISCC 编译失败(退出码 $code)。" }
if (-not (Test-Path $out)) { throw "未生成安装程序: $out" }

$sz = [math]::Round((Get-Item $out).Length / 1MB, 2)
Write-Host ""
Write-Host ("已生成: $out  ({0} MB)" -f $sz) -ForegroundColor Green
Get-Item $out | Select-Object Name, Length, LastWriteTime | Format-List