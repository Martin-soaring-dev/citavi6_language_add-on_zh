#!/usr/bin/env pwsh
<#
.SYNOPSIS
    生成可分发的语言包压缩包(dist/citavi6-<culture>-v<version>.zip)。

.DESCRIPTION
    1. 调用 Build-LanguagePack.ps1 构建(除非 -SkipBuild)。
    2. 校验关键文件存在。
    3. 打包 dist/<Culture>/ 为 zip,内含语言目录与安装说明。

.PARAMETER Version
    版本号,默认 0.1(第一版)。

.PARAMETER Culture
    语言目录名,默认 zh。

.EXAMPLE
    pwsh ./tools/Package-Release.ps1 -Version 0.1
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$Version = '0.1',

    [string]$Culture = 'zh',

    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$CultureDir = Join-Path $RepoDir "dist\$Culture"

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'Build-LanguagePack.ps1') -Culture $Culture -RepoDir $RepoDir
}

if (-not (Test-Path (Join-Path $CultureDir 'SwissAcademic.Resources.resources.dll'))) {
    throw "构建产物不完整:$CultureDir"
}

$stamp = Join-Path $RepoDir 'build\zip'
if (Test-Path $stamp) { Remove-Item $stamp -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stamp | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stamp $Culture) | Out-Null
Copy-Item (Join-Path $CultureDir '*.dll') (Join-Path $stamp $Culture) -Force

@"
Citavi 6 中文语言包 v$Version(社区汉化)

安装(推荐):双击本包中的「安装.vbs」(图形界面,无控制台)。
  - 自动检测 Citavi 6 与 Word 加载项目录,可手动修改;预览后一键安装/卸载。

手动安装:
1) 把本压缩包中的 "$Culture" 文件夹复制到 Citavi 安装目录的 bin\ 下,例如
   C:\Program Files (x86)\Citavi 6\bin\zh\
2) 如需 Word 加载项也显示中文,请把同一 "$Culture" 文件夹再复制到 Word 加载项目录,例如
   C:\Program Files\Microsoft Office\Root\Office16\ADDINS\Citavi Word AddIn\zh\
   (该目录由 Citavi 安装程序创建;若不存在可忽略此步)
3) 打开 Citavi -> 工具 -> 语言 -> 选择「中文」;随后重启 Word。

卸载:删除上述 zh 文件夹,并在语言菜单切回其他语言;或用「安装.vbs」里的“卸载”。

本语言包不修改 Citavi 任何原始文件。未翻译的条目会显示英文原文。
"@ | Set-Content -Path (Join-Path $stamp '安装说明.txt') -Encoding UTF8

# 图形安装器(双击 安装.vbs 启动,无控制台)+ CLI 备用
Copy-Item (Join-Path $PSScriptRoot 'Install-Gui.ps1') (Join-Path $stamp 'Install-Gui.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'Install-Toolkit.ps1') (Join-Path $stamp 'Install-Toolkit.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'gui-launcher.vbs') (Join-Path $stamp '安装.vbs') -Force

$zip = Join-Path $RepoDir "dist\citavi6-$Culture-v$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stamp '*') -DestinationPath $zip -Force

Remove-Item $stamp -Recurse -Force
Write-Host "已生成:$zip" -ForegroundColor Green
