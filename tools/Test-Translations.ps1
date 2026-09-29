#!/usr/bin/env pwsh
<#
.SYNOPSIS
    校验 translations/*.tsv 的格式与译文质量(占位符、列数、重复键)。

.DESCRIPTION
    逐文件检查:
      - 每行必须是 3 列(Tab 分隔),key 非空且在同一资源组内唯一;
      - 有译文的条目,`{0}`/`{1}` 等占位符集合必须与英文一致;
      - 译文不应为空串以外的异常(如全角化后的占位符)。
    退出码:0 全部通过;1 存在错误。

.PARAMETER Strict
    将警告(如译文含未转义的换行)视为错误。

.EXAMPLE
    pwsh ./tools/Test-Translations.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$TranslationsDir = '',

    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($TranslationsDir)) { $TranslationsDir = Join-Path $RepoDir 'translations' }

$phRegex = '\{[0-9]+\}'
function Get-Ph([string]$s) { (($phRegex | ForEach-Object { [regex]::Matches([string]$s, $_) } | ForEach-Object { $_.Value }) | Sort-Object) -join ',' }

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$stats = [ordered]@{ files = 0; keys = 0; translated = 0 }

foreach ($f in (Get-ChildItem $TranslationsDir -Recurse -Filter *.tsv | Sort-Object FullName)) {
    $stats.files++
    $seen = @{}
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ([string]::IsNullOrEmpty($line)) { continue }
        $rel = $f.FullName.Substring($TranslationsDir.Length).TrimStart('\')
        $p = $line -split "`t"
        if ($p.Count -ne 3) {
            $errors.Add("${rel}:$lineNo 列数=$($p.Count)(应为 3)")
            continue
        }
        if ([string]::IsNullOrEmpty($p[0])) { $errors.Add("${rel}:$lineNo key 为空"); continue }
        if ($seen.ContainsKey($p[0])) { $errors.Add("${rel}:$lineNo key 重复:$($p[0])"); continue }
        $seen[$p[0]] = $true
        $stats.keys++

        $zh = $p[2]
        if ([string]::IsNullOrEmpty($zh)) { continue }
        $stats.translated++

        $en = $p[1]
        if ((Get-Ph $en) -ne (Get-Ph $zh)) {
            $errors.Add("${rel}:$lineNo 占位符不一致 [$($p[0])]")
        }
        if ($zh -match '\\$') { $warnings.Add("${rel}:$lineNo 译文以反斜杠结尾 [$($p[0])]") }
        if ($p[1] -match '^\s' -or $p[1] -match '\s$') {
            if ((($zh -replace '^\s+','') -replace '\s+$','') -ne $zh) { } # 忽略
        }
    }
}

Write-Host ("文件 {0}  词条 {1}  已译 {2}  未译 {3}" -f $stats.files, $stats.keys, $stats.translated, ($stats.keys - $stats.translated))
Write-Host ("错误 {0}  警告 {1}" -f $errors.Count, $warnings.Count)

if ($warnings.Count) { $warnings | Select-Object -First 20 | ForEach-Object { Write-Host "  [警告] $_" -ForegroundColor Yellow } }
if ($errors.Count)   { $errors   | Select-Object -First 40 | ForEach-Object { Write-Host "  [错误] $_" -ForegroundColor Red } }

if ($errors.Count -gt 0 -or ($Strict -and $warnings.Count -gt 0)) { exit 1 }
exit 0
