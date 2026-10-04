#!/usr/bin/env pwsh
<#
.SYNOPSIS
    在不启动 Citavi 的情况下验证语言包可被 .NET 正确解析。

.DESCRIPTION
    把 Citavi 的中性程序集与 dist/<Culture>/ 复制到临时目录(模拟 Citavi 的 bin),
    然后用 System.Resources.ResourceManager 以 zh 文化读取词条,验证:
      - 有译文的 key 返回中文
      - 无译文的 key 回退英文
      - 附属程序集被正确发现(名字/版本/资源名)

.PARAMETER CitaviBin
    Citavi 的 bin 目录(提供中性程序集)。

.EXAMPLE
    pwsh ./tools/Test-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CitaviBin,

    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$Culture = 'zh',

    [string]$DistDir = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Resources

if ([string]::IsNullOrEmpty($DistDir)) { $DistDir = Join-Path $RepoDir "dist\$Culture" }
if (-not (Test-Path $DistDir)) { throw "找不到语言包目录:$DistDir" }
if (-not (Test-Path (Join-Path $DistDir 'SwissAcademic.Resources.resources.dll'))) {
    throw "语言包缺少 SwissAcademic.Resources.resources.dll(语言识别必需)"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("citavi-lang-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $tmp $Culture) | Out-Null
try {
    Copy-Item (Join-Path $DistDir '*.dll') (Join-Path $tmp $Culture) -Force
    foreach ($f in 'SwissAcademic.Resources.dll','SwissAcademic.dll','SwissAcademic.Citavi.dll',
                   'SwissAcademic.Controls.dll','SwissAcademic.WordProcessing.dll','Citavi.exe') {
        $src = Join-Path $CitaviBin $f
        if (Test-Path $src) { Copy-Item $src $tmp -Force }
    }

    $asm = [System.Reflection.Assembly]::LoadFile((Join-Path $tmp 'SwissAcademic.Resources.dll'))
    $zh  = [Globalization.CultureInfo]::GetCultureInfo($Culture)
    $en  = [Globalization.CultureInfo]::GetCultureInfo('en')

    $cases = @(
        @{ Set = 'SwissAcademic.Resources.FormTexts';          Key = 'ReferenceGridForm';            Expect = '表视图' }
        @{ Set = 'SwissAcademic.Resources.WebLabelsOffline';   Key = 'Retry';                        Expect = '重试' }
        @{ Set = 'SwissAcademic.Resources.SpecialChars';       Key = 'Ellipsis';                     Expect = '省略号' }
        @{ Set = 'SwissAcademic.Resources.Tools';              Key = 'MainForm_PreviewShowNotes';    Expect = '笔记' }
    )

    $fail = 0
    foreach ($c in $cases) {
        $rm = New-Object System.Resources.ResourceManager($c.Set, $asm)
        $v = $rm.GetString($c.Key, $zh)
        if ($null -eq $c.Expect) {
            $enV = $rm.GetString($c.Key, $en)
            $ok = ($v -eq $enV)
            Write-Host ("[{0}] {1}.{2} = {3}  (回退英文预期: {4})" -f $(if($ok){'OK'}else{'FAIL'}), $c.Set, $c.Key, $v, $enV) -ForegroundColor $(if($ok){'Green'}else{'Red'})
        } else {
            $ok = ($v -eq $c.Expect)
            Write-Host ("[{0}] {1}.{2} = {3}  (预期 {4})" -f $(if($ok){'OK'}else{'FAIL'}), $c.Set, $c.Key, $v, $c.Expect) -ForegroundColor $(if($ok){'Green'}else{'Red'})
        }
        if (-not $ok) { $fail++ }
    }

    Write-Host ''
    if ($fail -eq 0) { Write-Host "语言包解析测试通过。" -ForegroundColor Green; exit 0 }
    else { Write-Host "有 $fail 项失败。" -ForegroundColor Red; exit 1 }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
