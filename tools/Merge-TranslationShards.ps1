#!/usr/bin/env pwsh
<#
.SYNOPSIS
    合并子代理产出的分片译文(reference/shards/shard-*.zh.tsv)并回填 translations/*.tsv。

.DESCRIPTION
    1. 读取 reference/shards/index.json(id -> 英文)。
    2. 读取所有 shard-*.zh.tsv,格式 `<id>\t<中文>`。
    3. 校验 {n} 占位符一致;不一致的丢弃并报告。
    4. 写入 reference/mt-cache.json(英文 -> 中文)。
    5. 回填 translations/*.tsv 第 3 列(仅转义真实控制字符)。

.PARAMETER RequireAll
    要求所有分片都存在,否则报错退出。

.EXAMPLE
    pwsh ./tools/Merge-TranslationShards.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$ShardDir = '',

    [string]$CacheFile = '',

    [switch]$RequireAll
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ShardDir))  { $ShardDir  = Join-Path $RepoDir 'reference\shards' }
if ([string]::IsNullOrEmpty($CacheFile)) { $CacheFile = Join-Path $RepoDir 'reference\mt-cache.json' }

$indexPath = Join-Path $ShardDir 'index.json'
if (-not (Test-Path $indexPath)) { throw "找不到 $indexPath(请先运行 Prepare-TranslationShards.ps1)" }

$index = @{}
$obj = Get-Content $indexPath -Raw | ConvertFrom-Json
foreach ($p in $obj.PSObject.Properties) { $index[$p.Name] = $p.Value }

$cache = @{}
if (Test-Path $CacheFile) {
    try {
        $c = Get-Content $CacheFile -Raw | ConvertFrom-Json
        foreach ($p in $c.PSObject.Properties) { $cache[$p.Name] = $p.Value }
    } catch {}
}

$phRegex = '\{[0-9]+\}'
function Get-Ph([string]$s) { ((@([regex]::Matches([string]$s, $phRegex)) | ForEach-Object { $_.Value }) | Sort-Object) -join ',' }

$shardFiles = @(Get-ChildItem $ShardDir -Filter 'shard-*.zh.tsv' | Sort-Object Name)
$expected = @(Get-ChildItem $ShardDir -Filter 'shard-*.tsv' | Where-Object { $_.Name -notlike '*.zh.tsv' })
if ($RequireAll -and $shardFiles.Count -lt $expected.Count) {
    throw "分片不完整:期望 $($expected.Count) 个,实际 $($shardFiles.Count) 个"
}

$applied = 0; $bad = 0; $unknown = 0
foreach ($f in $shardFiles) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ([string]::IsNullOrEmpty($line)) { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 2) { Write-Warning "$($f.Name):$lineNo 列数不足"; $bad++; continue }
        $id = $p[0].Trim()
        $zh = $p[1]
        if (-not $index.ContainsKey($id)) { $unknown++; continue }
        if ([string]::IsNullOrEmpty($zh)) { continue }
        $en = $index[$id]
        if ((Get-Ph $en) -ne (Get-Ph $zh)) { Write-Warning "$($f.Name):$lineNo 占位符不一致(id=$id)"; $bad++; continue }
        $cache[$en] = $zh
        $applied++
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CacheFile) | Out-Null
$ordered = [ordered]@{}
foreach ($k in ($cache.Keys | Sort-Object)) { $ordered[$k] = $cache[$k] }
($ordered | ConvertTo-Json -Depth 3) | Set-Content -Path $CacheFile -Encoding UTF8
Write-Host "合并 $($shardFiles.Count)/$($expected.Count) 个分片:新增译文 $applied 条,占位符不符 $bad 条,未知 id $unknown 条,缓存共 $($cache.Count) 条"

# 回填
$utf8 = New-Object System.Text.UTF8Encoding($false)
$filled = 0
foreach ($f in (Get-ChildItem (Join-Path $RepoDir 'translations') -Recurse -Filter *.tsv | Sort-Object FullName)) {
    $out = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $p = $line -split "`t"
        if ($p.Count -ge 3 -and [string]::IsNullOrEmpty($p[2]) -and $cache.ContainsKey($p[1])) {
            $zh = $cache[$p[1]]
            if (-not [string]::IsNullOrEmpty($zh)) {
                $p[2] = $zh.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
                $changed = $true; $filled++
            }
        }
        $out.Add(($p -join "`t"))
    }
    if ($changed) { [System.IO.File]::WriteAllLines($f.FullName, $out, $utf8) }
}
Write-Host "已回填 $filled 条译文到 translations/。" -ForegroundColor Green
