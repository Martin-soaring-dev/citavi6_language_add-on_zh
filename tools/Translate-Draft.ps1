#!/usr/bin/env pwsh
<#
.SYNOPSIS
    为 translations/*.tsv 中未翻译的条目生成机翻初稿(填充第 3 列)。

.DESCRIPTION
    使用在线机翻(Google dict-chrome-ex 端点)生成初稿,结果缓存到
    reference/mt-cache.json(可断点续传):
      - 以"英文原文"为缓存键,跨资源组去重(相同原文只翻一次);
      - 批量翻译:一次请求携带多个 q 参数,按顺序返回数组;
      - 校验:返回条数一致、{n} 占位符数量一致;不通过则降级为单条重试;
      - 节流 + 429 退避重试。

    ⚠️ 机翻初稿仅供人工校对;正式版建议替换为正规翻译 API。

.PARAMETER Only
    仅处理路径包含该子串的资源组(调试用)。

.PARAMETER Limit
    最多翻译多少条未翻译原文(调试用)。

.PARAMETER BatchSize
    每批条数,默认 20。

.PARAMETER MaxChars
    每批原文总字符上限,默认 1200。

.EXAMPLE
    pwsh ./tools/Translate-Draft.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$TranslationsDir = '',

    [string]$CacheFile = '',

    [string]$TargetLang = 'zh-CN',

    [string]$Only = '',

    [int]$Limit = 0,

    [int]$BatchSize = 20,

    [int]$MaxChars = 1200,

    [int]$DelayMs = 350,

    [int]$MaxRetries = 6
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($TranslationsDir)) { $TranslationsDir = Join-Path $RepoDir 'translations' }
if ([string]::IsNullOrEmpty($CacheFile))       { $CacheFile       = Join-Path $RepoDir 'reference\mt-cache.json' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CacheFile) | Out-Null

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(45)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept-Language', 'en-US,en;q=0.9') | Out-Null
$client.DefaultRequestHeaders.Referrer = [uri]'https://translate.google.com/'

$script:requestCount = 0
$script:delayMs = $DelayMs
$script:pendingTotal = 0
$script:done = 0
$script:fail = 0

function Invoke-Translate {
    param([string[]]$Lines)
    $u = "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=en&tl=$TargetLang"
    foreach ($l in $Lines) { $u += '&q=' + [uri]::EscapeDataString($l) }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $script:requestCount++
            $body = $client.GetStringAsync($u).GetAwaiter().GetResult()
            return ($body | ConvertFrom-Json)
        } catch {
            $status = 0
            try { $status = [int]$_.Exception.InnerException.Response.StatusCode } catch {}
            if ($attempt -ge $MaxRetries) { throw "翻译请求失败($attempt 次,HTTP $status):$($_.Exception.Message)" }
            $wait = [Math]::Min(20, [Math]::Pow(2, $attempt))
            if ($status -eq 429) { $script:delayMs = [Math]::Min(4000, $script:delayMs + 300) }
            Write-Warning "请求失败(HTTP $status),${wait}s 后重试($attempt/$MaxRetries)"
            Start-Sleep -Seconds $wait
        }
    }
}

# 返回与 $Lines 等长的译文数组;无法对齐时返回 $null
function Parse-Batch {
    param($Response, [string[]]$Lines)
    if ($null -eq $Response) { return $null }
    $arr = @($Response)
    if ($arr.Count -ne $Lines.Count) { return $null }
    $out = New-Object string[] $Lines.Count
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $v = $arr[$i]
        if ($v -is [System.Array]) { $out[$i] = ($v -join '') } else { $out[$i] = [string]$v }
    }
    return $out
}

$phRegex = '\{[0-9]+\}'
function Get-Ph([string]$s) { ((@([regex]::Matches([string]$s, $phRegex)) | ForEach-Object { $_.Value }) | Sort-Object) -join ',' }

# ---------- 缓存 ----------
$cache = @{}
if (Test-Path $CacheFile) {
    try {
        $obj = Get-Content $CacheFile -Raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $cache[$p.Name] = $p.Value }
        Write-Host "已加载缓存:$($cache.Count) 条"
    } catch { Write-Warning "缓存文件损坏,忽略:$($_.Exception.Message)" }
}
function Save-Cache {
    $ordered = [ordered]@{}
    foreach ($k in ($cache.Keys | Sort-Object)) { $ordered[$k] = $cache[$k] }
    ($ordered | ConvertTo-Json -Depth 3) | Set-Content -Path $CacheFile -Encoding UTF8
}

# ---------- 收集 ----------
$files = Get-ChildItem $TranslationsDir -Recurse -Filter *.tsv | Sort-Object FullName
if ($Only) { $files = @($files | Where-Object { $_.FullName -like "*$Only*" }) }

$pending = [System.Collections.Generic.List[string]]::new()
$seen = @{}
foreach ($f in $files) {
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 3) { continue }
        $en = $p[1]
        if ([string]::IsNullOrEmpty($en)) { continue }
        if (-not [string]::IsNullOrEmpty($p[2])) { continue }
        if ($cache.ContainsKey($en) -or $seen.ContainsKey($en)) { continue }
        if ($en -notmatch '[A-Za-z]') { $cache[$en] = $en; continue }   # 纯符号/数字,原样
        $seen[$en] = $true
        $pending.Add($en)
    }
}
if ($Limit -gt 0 -and $pending.Count -gt $Limit) { $pending = $pending[0..($Limit - 1)] }
$script:pendingTotal = $pending.Count
Write-Host "待翻译唯一原文:$($pending.Count) 条"

# ---------- 翻译 ----------
function Translate-Items {
    param([string[]]$Lines)
    try {
        $resp = Invoke-Translate -Lines $Lines
        $result = Parse-Batch -Response $resp -Lines $Lines
        if ($null -ne $result) { return $result }
    } catch { Write-Warning $_ }

    # 降级:逐条
    $out = New-Object string[] $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        try {
            $resp = Invoke-Translate -Lines @($Lines[$i])
            $r = @(Parse-Batch -Response $resp -Lines @($Lines[$i]))
            if ($r.Count -ge 1 -and $null -ne $r[0]) { $out[$i] = [string]$r[0] }
        } catch { Write-Warning $_ }
        Start-Sleep -Milliseconds $script:delayMs
    }
    return $out
}

$batch = [System.Collections.Generic.List[string]]::new()
$chars = 0
$batchesDone = 0
function Submit-Batch {
    param([string[]]$lines)
    if ($lines.Count -eq 0) { return }
    $result = @(Translate-Items -Lines $lines)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $zh = if ($i -lt $result.Count -and $null -ne $result[$i]) { ([string]$result[$i]).Trim() } else { '' }
        if ([string]::IsNullOrEmpty($zh)) { $script:fail++; continue }
        if ((Get-Ph $lines[$i]) -ne (Get-Ph $zh)) { Write-Warning "占位符不一致,丢弃:$($lines[$i])"; $script:fail++; continue }
        $cache[$lines[$i]] = $zh
    }
    $script:done += $lines.Count
    $script:batchesDone++
    if (($script:batchesDone % 10) -eq 0) {
        Save-Cache
        Write-Host ("  进度 {0}/{1}  请求 {2}  失败 {3}  (间隔 {4}ms)" -f $script:done, $script:pendingTotal, $script:requestCount, $script:fail, $script:delayMs)
    }
    Start-Sleep -Milliseconds $script:delayMs
}

foreach ($en in $pending) {
    if ($batch.Count -ge $BatchSize -or ($batch.Count -gt 0 -and ($chars + $en.Length) -gt $MaxChars)) {
        Submit-Batch -lines @($batch)
        $batch.Clear(); $chars = 0
    }
    $batch.Add($en); $chars += $en.Length + 1
}
if ($batch.Count -gt 0) { Submit-Batch -lines @($batch) }
Save-Cache
Write-Host ''
Write-Host "机翻完成:处理 $script:done 条,失败 $script:fail 条,缓存共 $($cache.Count) 条,请求 $script:requestCount 次" -ForegroundColor Green

# ---------- 回填 ----------
$filled = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($f in $files) {
    $out = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $p = $line -split "`t"
        if ($p.Count -ge 3 -and [string]::IsNullOrEmpty($p[2]) -and $cache.ContainsKey($p[1])) {
            $zh = $cache[$p[1]]
            if (-not [string]::IsNullOrEmpty($zh)) { $p[2] = $zh; $changed = $true; $filled++ }
        }
        $out.Add(($p -join "`t"))
    }
    if ($changed) { [System.IO.File]::WriteAllLines($f.FullName, $out, $utf8) }
}
Write-Host "已回填 $filled 条译文到 translations/。" -ForegroundColor Green
