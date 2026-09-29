#!/usr/bin/env pwsh
<#
.SYNOPSIS
    把待翻译的英文词条切分成若干分片,供子代理(模型)分批翻译。

.DESCRIPTION
    扫描 translations/*.tsv 中尚未翻译的词条(去重、跳过含 | 的内部数据、跳过纯符号),
    输出到 reference/shards/:
      - index.json        : { "<id>": "<english>" }      合并时用 id 还原英文
      - shard-000.tsv     : "<id>\t<english>"            每个分片一份,交给一个子代理
      - manifest.json     : 分片清单

    英文原文一律转义为单行(沿用提取时的 \\t \\r \\n 约定),因此可以直接按行切分。

.PARAMETER ShardSize
    每个分片的词条数,默认 250。

.PARAMETER MaxShards
    最多生成多少个分片,0 表示不限(调试用)。

.PARAMETER IncludePipes
    也纳入含 | 的内部数据(默认跳过)。

.EXAMPLE
    pwsh ./tools/Prepare-TranslationShards.ps1 -ShardSize 250
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [int]$ShardSize = 250,

    [int]$MaxShards = 0,

    [switch]$IncludePipes
)

$ErrorActionPreference = 'Stop'

$translationsDir = Join-Path $RepoDir 'translations'
$shardDir = Join-Path $RepoDir 'reference\shards'
$cacheFile = Join-Path $RepoDir 'reference\mt-cache.json'

# 已完成的译文(缓存)
$done = @{}
if (Test-Path $cacheFile) {
    try {
        $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $done[$p.Name] = $p.Value }
    } catch { Write-Warning "缓存损坏,忽略。" }
}

# 收集待翻译(按英文原文去重)
$pending = [System.Collections.Generic.List[string]]::new()
$seen = @{}
$skipped = 0
foreach ($f in (Get-ChildItem $translationsDir -Recurse -Filter *.tsv | Sort-Object FullName)) {
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 3) { continue }
        $en = $p[1]
        if ([string]::IsNullOrEmpty($en)) { continue }
        if (-not [string]::IsNullOrEmpty($p[2])) { continue }
        if ($done.ContainsKey($en) -or $seen.ContainsKey($en)) { continue }
        if ($en -notmatch '[A-Za-z]') { $seen[$en] = $true; continue }
        if (-not $IncludePipes -and $en.Contains('|')) { $skipped++; continue }
        $seen[$en] = $true
        $pending.Add($en)
    }
}

Write-Host "待翻译唯一原文:$($pending.Count) 条(跳过内部数据 $skipped 条)"

if (Test-Path $shardDir) { Remove-Item $shardDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $shardDir | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)
$index = [ordered]@{}
$shards = [System.Collections.Generic.List[object]]::new()
$shardNo = 0
$id = 0

for ($offset = 0; $offset -lt $pending.Count; $offset += $ShardSize) {
    if ($MaxShards -gt 0 -and $shardNo -ge $MaxShards) { break }
    $slice = $pending[$offset..([Math]::Min($offset + $ShardSize - 1, $pending.Count - 1))]
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($en in $slice) {
        $id++
        $index["$id"] = $en
        $lines.Add("$id`t$en")
    }
    $name = 'shard-{0:d3}.tsv' -f $shardNo
    [System.IO.File]::WriteAllLines((Join-Path $shardDir $name), $lines, $utf8)
    $shards.Add([pscustomobject]@{ shard = $name; count = $slice.Count; from = ($id - $slice.Count + 1); to = $id })
    $shardNo++
}

($index | ConvertTo-Json -Depth 2) | Set-Content -Path (Join-Path $shardDir 'index.json') -Encoding UTF8
($shards | ConvertTo-Json -Depth 3) | Set-Content -Path (Join-Path $shardDir 'manifest.json') -Encoding UTF8

Write-Host "已生成 $shardNo 个分片 -> $shardDir" -ForegroundColor Green
Write-Host ("  期望产出:每个 shard-XXX.tsv 对应一个 shard-XXX.zh.tsv,格式 '<id>`t<中文>'")
