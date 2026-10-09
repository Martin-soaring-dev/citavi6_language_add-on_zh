#!/usr/bin/env pwsh
<#
.SYNOPSIS
    校验 translations/*.tsv 的格式与译文质量(占位符、列数、重复键)。

.DESCRIPTION
    逐文件检查:
      - 每行必须是 3 列(Tab 分隔),key 非空且在同一资源组内唯一;
      - 有译文的条目,`{0}`/`{1}` 等占位符集合必须与英文一致;
      - SmartFormat 条件 `{n:…|…}`:起点 `{n:` 多重集与分支 `|` 数量须与英文一致;
      - HTML 标签(白名单)名称多重集须与英文一致(不把 `<Project name>` 之类伪标签算作 HTML);
      - RTF 条目反转义后必须以 `{\rtf` 开头(防止 `\\` 被误写成 `\` 而损坏);
      - 反斜杠转义规范:字面反斜杠须写成 `\\`。
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

function Get-SmartStarts([string]$s) {
    @([regex]::Matches($s, '\{[0-9]+:') | ForEach-Object { $_.Value } | Sort-Object) -join ','
}

# 只认常见 HTML 标签,避免把 <Project name> / <not given> 之类伪标签算进来
$htmlTagPattern = '</?(?:a|abbr|b|blockquote|br|code|dd|div|dl|dt|em|font|h1|h2|h3|h4|h5|h6|hr|i|img|li|ol|p|pre|small|span|strong|sub|sup|table|tbody|td|tfoot|th|thead|tr|u|ul)(?=[\s/>])'
function Get-HtmlTags([string]$s) {
    @([regex]::Matches($s, $htmlTagPattern) | ForEach-Object {
        if ($_.Value.StartsWith('</')) { '/' + $_.Value.Substring(2).TrimEnd('>', '/').Trim() }
        else { $_.Value.Substring(1).TrimEnd('>', '/').Trim() -replace '\s.*$', '' }
    } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object) -join ','
}

# 奇数长度的反斜杠串后面不是 r/n/t(或到串尾) => 该反斜杠未按规范写成 \\,反转义会引入非法控制符
$escapeBad = '(?<!\\)\\(?:\\\\)*(?:[^\\rnt]|$)'

# 与 Build-LanguagePack.ps1 一致的 TSV 字段反转义
function ConvertFrom-TsvField {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    return [regex]::Replace($Value, '\\.', {
        param($m)
        switch ($m.Value) {
            '\\' { '\' }
            '\t' { "`t" }
            '\r' { "`r" }
            '\n' { "`n" }
            default { $m.Value }
        }
    })
}

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

        $enSmart = Get-SmartStarts $en
        $zhSmart = Get-SmartStarts $zh
        if ($enSmart -or $zhSmart) {
            if ($enSmart -ne $zhSmart) {
                $errors.Add("${rel}:$lineNo SmartFormat 条件起点不一致 [$($p[0])] EN={$enSmart} ZH={$zhSmart}")
            } else {
                $enPipe = ([regex]::Matches($en, '\|')).Count
                $zhPipe = ([regex]::Matches($zh, '\|')).Count
                if ($enPipe -ne $zhPipe) {
                    $errors.Add("${rel}:$lineNo SmartFormat 分支 | 数量不一致(EN=$enPipe ZH=$zhPipe) [$($p[0])]")
                }
            }
        }

        $enHtml = Get-HtmlTags $en
        $zhHtml = Get-HtmlTags $zh
        if (($enHtml -or $zhHtml) -and ($enHtml -ne $zhHtml)) {
            $errors.Add("${rel}:$lineNo HTML 标签不一致 [$($p[0])] EN={$enHtml} ZH={$zhHtml}")
        }

        if ($zh -match $escapeBad) {
            $warnings.Add("${rel}:$lineNo 非规范反斜杠转义(字面反斜杠应写成 \\ ) [$($p[0])]")
        }
        if (([string](ConvertFrom-TsvField $en)).StartsWith('{\rtf')) {
            $zhU = [string](ConvertFrom-TsvField $zh)
            if (-not $zhU.StartsWith('{\rtf')) {
                $head = if ($zhU.Length -gt 8) { $zhU.Substring(0, 8) } else { $zhU }
                $errors.Add("${rel}:$lineNo RTF 转义损坏:反转义后应以 {\rtf 开头,实际 '$head' [$($p[0])]")
            }
        }
    }
}

Write-Host ("文件 {0}  词条 {1}  已译 {2}  未译 {3}" -f $stats.files, $stats.keys, $stats.translated, ($stats.keys - $stats.translated))
Write-Host ("错误 {0}  警告 {1}" -f $errors.Count, $warnings.Count)

if ($warnings.Count) { $warnings | Select-Object -First 20 | ForEach-Object { Write-Host "  [警告] $_" -ForegroundColor Yellow } }
if ($errors.Count)   { $errors   | Select-Object -First 40 | ForEach-Object { Write-Host "  [错误] $_" -ForegroundColor Red } }

if ($errors.Count -gt 0 -or ($Strict -and $warnings.Count -gt 0)) { exit 1 }
exit 0
