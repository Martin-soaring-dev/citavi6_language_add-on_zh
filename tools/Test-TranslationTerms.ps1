#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Audit terminology candidates and inconsistent translations without changing source files.
.DESCRIPTION
    Reports legacy terminology candidates from the third TSV column and cases where
    identical English source strings have multiple Chinese translations. The default
    mode is report-only because some terms legitimately depend on context. Use -Strict
    only after reviewing the current candidate list and documenting exceptions.
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),
    [string]$TranslationsDir = '',
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($TranslationsDir)) {
    $TranslationsDir = Join-Path $RepoDir 'translations'
}
if (-not (Test-Path -LiteralPath $TranslationsDir -PathType Container)) {
    throw "Translations directory not found: $TranslationsDir"
}

# These are review candidates, not automatic replacements: context can justify exceptions.
$rules = @(
    @{ Pattern = '关键字'; Preferred = '关键词'; Label = 'Keyword' }
    @{ Pattern = '脱机'; Preferred = '离线'; Label = 'Offline' }
    @{ Pattern = '过滤器'; Preferred = '筛选器'; Label = 'Filter' }
    @{ Pattern = '出版商'; Preferred = '出版社'; Label = 'Publisher' }
    @{ Pattern = '帐户'; Preferred = '账户'; Label = 'Account' }
    @{ Pattern = '兑换码'; Preferred = '优惠券代码'; Label = 'Voucher code' }
    @{ Pattern = '题录'; Preferred = '文献'; Label = 'Reference terminology' }
    @{ Pattern = '备注'; Preferred = '笔记'; Label = 'Note' }
    @{ Pattern = '媒介'; Preferred = '存储介质'; Label = 'Storage medium' }
)

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($file in (Get-ChildItem -LiteralPath $TranslationsDir -Recurse -Filter '*.tsv' | Sort-Object FullName)) {
    $lineNo = 0
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        $lineNo++
        if ([string]::IsNullOrEmpty($line)) { continue }
        $parts = $line.Split([char]9)
        if ($parts.Length -ne 3 -or [string]::IsNullOrWhiteSpace($parts[2])) { continue }
        $rows.Add([pscustomobject]@{
            File = $file.FullName.Substring($TranslationsDir.Length).TrimStart('\', '/')
            Line = $lineNo
            Key = $parts[0]
            English = $parts[1]
            Chinese = $parts[2]
        })
    }
}

$termFindings = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    foreach ($rule in $rules) {
        if ($row.Chinese.Contains($rule.Pattern)) {
            $termFindings.Add([pscustomobject]@{
                File = $row.File
                Line = $row.Line
                Key = $row.Key
                Term = $rule.Label
                Candidate = $rule.Pattern
                Preferred = $rule.Preferred
                Chinese = $row.Chinese
            })
        }
    }
}

$duplicateFindings = [System.Collections.Generic.List[object]]::new()
$groups = $rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.English) } |
    Group-Object -Property English
foreach ($group in $groups) {
    $variants = @($group.Group | Select-Object -ExpandProperty Chinese -Unique)
    if ($variants.Count -gt 1) {
        foreach ($row in $group.Group) {
            $duplicateFindings.Add([pscustomobject]@{
                English = $row.English
                ChineseVariants = ($variants -join ' | ')
                File = $row.File
                Line = $row.Line
                Key = $row.Key
                Chinese = $row.Chinese
            })
        }
    }
}

Write-Host ("译文审查: {0} 个已译词条;术语候选 {1} 条;同源译法不一致候选 {2} 条。" -f $rows.Count, $termFindings.Count, $duplicateFindings.Count)
if ($termFindings.Count -gt 0) {
    Write-Host '术语候选(需按语境人工确认):'
    $termFindings | Select-Object -First 80 | ForEach-Object {
        Write-Host ("  {0}:{1} [{2}] {3} -> 建议核对「{4}」;当前: {5}" -f $_.File, $_.Line, $_.Key, $_.Candidate, $_.Preferred, $_.Chinese)
    }
    if ($termFindings.Count -gt 80) { Write-Host ("  ...另有 {0} 条术语候选未显示。" -f ($termFindings.Count - 80)) }
}
if ($duplicateFindings.Count -gt 0) {
    Write-Host '同一英文原文的多种译法候选(前 80 条;需按语境人工确认):'
    $duplicateFindings | Select-Object -First 80 | ForEach-Object {
        Write-Host ("  {0}:{1} [{2}] EN={3} | ZH={4}" -f $_.File, $_.Line, $_.Key, $_.English, $_.ChineseVariants)
    }
    if ($duplicateFindings.Count -gt 80) { Write-Host ("  ...另有 {0} 条同源译法候选未显示。" -f ($duplicateFindings.Count - 80)) }
}

if ($Strict -and ($termFindings.Count -gt 0 -or $duplicateFindings.Count -gt 0)) {
    throw '严格术语审查发现候选项；请先人工确认并记录语境例外。'
}
Write-Host '审查报告完成；此脚本不会自动改写译文。'
