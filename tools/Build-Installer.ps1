#!/usr/bin/env pwsh
<#
.SYNOPSIS
    用 Inno Setup 把语言包 + 快速帮助打包成单文件安装程序(Setup.exe)。
.DESCRIPTION
    依赖 Inno Setup 6/7 的 ISCC.exe(可用 winget install JRSoftware.InnoSetup 安装)。
    产物: dist/Citavi6-zh-Setup-v<版本>.exe
.EXAMPLE
    pwsh ./tools/Build-Installer.ps1 -Version 0.103
#>
[CmdletBinding()]
param(
    [string]$Version = '0.103',
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

# 品牌位图资产(.iss 里 SetupIconFile/WizardImageFile/WizardSmallImageFile 依赖它们)
$BrandDir = Join-Path $Repo 'docs\brand\simple\export\win'
$BrandAssets = @('setup.ico', 'wizard-image.png', 'wizard-small.png')
$missing = @($BrandAssets | Where-Object { -not (Test-Path (Join-Path $BrandDir $_)) })
if ($missing.Count) {
    throw ("缺少品牌位图资产: {0}(在 {1})。先运行 pwsh ./tools/Build-BrandAssets.ps1 生成。" -f ($missing -join ', '), $BrandDir)
}
$brandKB = [math]::Round((($BrandAssets | ForEach-Object { (Get-Item (Join-Path $BrandDir $_)).Length } | Measure-Object -Sum).Sum) / 1KB, 1)
Write-Host ("品牌资产: {0}({1} KB)" -f ($BrandAssets -join ', '), $brandKB)

# 许可页与装完提示页(.iss 的 LicenseFile / InfoAfterFile)
$InstDir = Join-Path $PSScriptRoot 'installer'
foreach ($t in @('license.zh.txt', 'infoafter.zh.txt')) {
    $tp = Join-Path $InstDir $t
    if (-not (Test-Path $tp)) { throw "缺少安装程序文本文件: $tp" }
    # Inno 只承诺 UTF-8/UTF-16LE 编码,未承诺纯 LF 能正常换行;.gitattributes 已钉 eol=crlf,这里兜底。
    if (([IO.File]::ReadAllText($tp)) -notmatch "`r`n") { throw "$t 不是 CRLF 换行,许可页可能整页挤成一行。" }
}

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