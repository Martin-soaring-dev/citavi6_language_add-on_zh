#!/usr/bin/env pwsh
<#
.SYNOPSIS
    把 dist/<Culture>/ 安装到 Citavi 6 的 bin 目录(或卸载)。

.DESCRIPTION
    将语言包复制为 <CitaviBin>/<Culture>/(例如 ...\Citavi 6\bin\zh\)。
    安装后 Citavi 的语言菜单会出现对应语言;卸载则是删除该目录。

    向 Program Files 写入通常需要管理员权限,请在提权的终端中运行。

.PARAMETER CitaviBin
    Citavi 的 bin 目录,例如 "C:\Program Files (x86)\Citavi 6\bin"。

.PARAMETER SourceDir
    语言包源目录,默认 <仓库>/dist/<Culture>。

.PARAMETER Culture
    目标目录名,默认 zh。

.PARAMETER Uninstall
    卸载:删除 <CitaviBin>/<Culture>。

.EXAMPLE
    pwsh ./tools/Install-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"
    pwsh ./tools/Install-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin" -Uninstall
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CitaviBin,

    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$Culture = 'zh',

    [string]$SourceDir = '',

    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($SourceDir)) { $SourceDir = Join-Path $RepoDir "dist\$Culture" }
$CitaviBin = (Resolve-Path $CitaviBin).Path
$target = Join-Path $CitaviBin $Culture

if (-not (Test-Path (Join-Path $CitaviBin 'SwissAcademic.dll'))) {
    throw "不是有效的 Citavi bin 目录(缺少 SwissAcademic.dll):$CitaviBin"
}

if ($Uninstall) {
    if (Test-Path $target) {
        Remove-Item $target -Recurse -Force
        Write-Host "已卸载:已删除 $target" -ForegroundColor Green
        Write-Host "请在 Citavi 中「工具 → 语言」切换回其他语言。"
    } else {
        Write-Host "未安装:$target 不存在。" -ForegroundColor Yellow
    }
    return
}

if (-not (Test-Path $SourceDir)) { throw "找不到语言包源目录:$SourceDir" }
if (-not (Test-Path (Join-Path $SourceDir 'SwissAcademic.Resources.resources.dll'))) {
    throw "语言包缺少 SwissAcademic.Resources.resources.dll(语言识别必需):$SourceDir"
}

try {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item (Join-Path $SourceDir '*.dll') $target -Force
} catch [System.UnauthorizedAccessException] {
    throw "写入被拒绝。请以管理员身份重新运行 PowerShell,或改用带提权的终端。原始错误:$($_.Exception.Message)"
}

$count = @(Get-ChildItem $target -Filter *.dll).Count
Write-Host "已安装 $count 个文件到 $target" -ForegroundColor Green
Write-Host ''
Write-Host "下一步:打开 Citavi → 工具(Tools)→ 语言(Language)→ 选择「中文」。"
Write-Host "若未立即生效,请重启 Citavi。"
