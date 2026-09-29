#!/usr/bin/env pwsh
<#
.SYNOPSIS
    从 Citavi 6 安装目录提取英文字典,生成 translations/*.tsv。

.DESCRIPTION
    读取 Citavi 中性(英文)程序集内嵌的 .resources,导出为 UTF-8 无 BOM 的
    Tab 分隔文件:

        key <TAB> English <TAB> 中文

    - 第 3 列(中文)在 -Force 时留空,否则保留已有译文。
    - 非字符串条目(如 int)写入 reference/nonstring/,供 Build 还原。
    - 需要 Citavi 6 安装目录。

.PARAMETER CitaviBin
    Citavi 的 bin 目录,例如 "C:\Program Files (x86)\Citavi 6\bin"。

.PARAMETER RepoDir
    仓库根目录,默认自动推断。

.PARAMETER Force
    重建翻译文件,丢弃已有译文(危险)。

.PARAMETER Diff
    只报告与已有译文的差异,不写文件。

.EXAMPLE
    pwsh ./tools/Extract-Resources.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CitaviBin,

    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [switch]$Force,

    [switch]$Diff
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Resources

if (-not (Test-Path (Join-Path $CitaviBin 'SwissAcademic.dll'))) {
    throw "不是有效的 Citavi bin 目录(缺少 SwissAcademic.dll):$CitaviBin"
}

$TranslationsDir = Join-Path $RepoDir 'translations'
$ReferenceDir    = Join-Path $RepoDir 'reference'

# 目标:中性程序集 -> 语言包目录名(= 程序集名)与父程序集版本
$Targets = @(
    [pscustomobject]@{ File = 'Citavi.exe';                          Assembly = 'Citavi';                          Version = '5.8.0.0' }
    [pscustomobject]@{ File = 'SwissAcademic.dll';                   Assembly = 'SwissAcademic';                   Version = '5.8.0.0' }
    [pscustomobject]@{ File = 'SwissAcademic.Citavi.dll';            Assembly = 'SwissAcademic.Citavi';            Version = '5.8.0.0' }
    [pscustomobject]@{ File = 'SwissAcademic.Controls.dll';          Assembly = 'SwissAcademic.Controls';          Version = '5.8.0.0' }
    [pscustomobject]@{ File = 'SwissAcademic.Resources.dll';         Assembly = 'SwissAcademic.Resources';         Version = '6.0.0.0' }
    [pscustomobject]@{ File = 'SwissAcademic.WordProcessing.dll';    Assembly = 'SwissAcademic.WordProcessing';    Version = '5.8.0.0' }
)

# 不作为 UI 翻译目标的资源组
$SkipGroups = @(
    'SwissAcademic.Resources.CRMde'   # 官方德语版邮件模板
)

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-TsvField {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    # 先转义反斜杠,再转义控制字符
    $Value.Replace('\', '\\').Replace("`t", '\t').Replace("`r", '\r').Replace("`n", '\n')
}

function Read-ExistingTranslations {
    param([string]$Path)
    # 返回:key -> 译文(可能为空字符串)。用于保留已有译文以及 Diff 判断 key 是否已存在。
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -ge 1 -and -not [string]::IsNullOrEmpty($parts[0])) {
            $zh = if ($parts.Count -ge 3) { $parts[2] } else { '' }
            $map[$parts[0]] = $zh
        }
    }
    return $map
}

function Get-ResourceEntries {
    param([string]$AssemblyPath, [string]$ResourceName)
    $result = [pscustomobject]@{
        Strings    = [System.Collections.Generic.List[object]]::new()
        NonStrings = [System.Collections.Generic.List[object]]::new()
    }
    $asm = [System.Reflection.Assembly]::LoadFile($AssemblyPath)
    $stream = $asm.GetManifestResourceStream($ResourceName)
    if (-not $stream) { return $result }
    try {
        $reader = New-Object System.Resources.ResourceReader($stream)
        $e = $reader.GetEnumerator()
        while ($e.MoveNext()) {
            $key   = $e.Current.Key
            $value = $e.Current.Value
            if ([string]::IsNullOrEmpty($key)) { continue }
            if ($value -is [string]) {
                $result.Strings.Add([pscustomobject]@{ Key = $key; Value = $value })
            }
            elseif ($null -ne $value) {
                $result.NonStrings.Add([pscustomobject]@{ Key = $key; Value = $value })
            }
        }
    }
    finally { $stream.Dispose() }
    return $result
}

$manifest = [System.Collections.Generic.List[object]]::new()
$totals   = [ordered]@{ groups = 0; keys = 0; nonStrings = 0; added = 0; removed = 0; kept = 0 }

foreach ($t in $Targets) {
    $assemblyPath = Join-Path $CitaviBin $t.File
    if (-not (Test-Path $assemblyPath)) {
        Write-Warning "跳过缺失的程序集:$($t.File)"
        continue
    }
    $asm = [System.Reflection.Assembly]::LoadFile($assemblyPath)
    $groups = @($asm.GetManifestResourceNames() | Where-Object { $_.EndsWith('.resources') }) | Sort-Object
    if ($groups.Count -eq 0) {
        Write-Warning "$($t.File) 没有内嵌资源。"
        continue
    }

    $outAssemblyDir = Join-Path $TranslationsDir $t.Assembly
    $nonStringDir   = Join-Path $ReferenceDir 'nonstring' $t.Assembly

    $groupInfo = [System.Collections.Generic.List[object]]::new()

    foreach ($rn in $groups) {
        $baseName = $rn.Substring(0, $rn.Length - '.resources'.Length)
        if ($SkipGroups -contains $baseName) { continue }

        $entries = Get-ResourceEntries -AssemblyPath $assemblyPath -ResourceName $rn
        if ($entries.Strings.Count -eq 0) { continue }   # 非文本组(如 Icons)跳过

        $totals.groups++
        $totals.keys += $entries.Strings.Count
        $groupInfo.Add([pscustomobject]@{ Group = $baseName; Keys = $entries.Strings.Count; NonStrings = $entries.NonStrings.Count })

        # 非字符串条目 -> reference/nonstring
        if ($entries.NonStrings.Count -gt 0) {
            New-Item -ItemType Directory -Force -Path $nonStringDir | Out-Null
            $nsLines = [System.Collections.Generic.List[string]]::new()
            foreach ($ns in $entries.NonStrings) {
                $type = $ns.Value.GetType()
                $code = [Type]::GetTypeCode($type)
                if ($code -eq [TypeCode]::Object -or $code -eq [TypeCode]::Empty) {
                    Write-Warning "  跳过无法序列化的条目:$rn :: $($ns.Key) ($($type.FullName))"
                    continue
                }
                $str = if ($type -eq [datetime]) { ([datetime]$ns.Value).ToString('o') } else { [Convert]::ToString($ns.Value, [Globalization.CultureInfo]::InvariantCulture) }
                $nsLines.Add("$($ns.Key)`t$code`t$str")
                $totals.nonStrings++
            }
            [System.IO.File]::WriteAllLines((Join-Path $nonStringDir "$baseName.tsv"), $nsLines, $Utf8NoBom)
        }

        # 字符串条目 -> translations
        New-Item -ItemType Directory -Force -Path $outAssemblyDir | Out-Null
        $outFile = Join-Path $outAssemblyDir "$baseName.tsv"

        if ($Diff) {
            if (-not (Test-Path $outFile)) {
                Write-Host "[新增] $($t.Assembly)/$baseName.tsv ($($entries.Strings.Count) 条)" -ForegroundColor Green
            } else {
                $existing = Read-ExistingTranslations $outFile
                $srcKeys  = @{}
                foreach ($s in $entries.Strings) { $srcKeys[$s.Key] = $true }
                $added   = @($srcKeys.Keys | Where-Object { -not $existing.ContainsKey($_) })
                $removed = @($existing.Keys | Where-Object { -not $srcKeys.ContainsKey($_) })
                if ($added.Count -or $removed.Count) {
                    Write-Host "[变化] $($t.Assembly)/$baseName.tsv  新增 $($added.Count),移除 $($removed.Count)"
                }
            }
            continue
        }

        $existing = if ($Force) { @{} } else { Read-ExistingTranslations $outFile }
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($s in $entries.Strings) {
            $zh = ''
            if ($existing.ContainsKey($s.Key)) {
                $zh = $existing[$s.Key]
                if (-not [string]::IsNullOrEmpty($zh)) { $totals.kept++ }
            }
            $lines.Add("$($s.Key)`t$(ConvertTo-TsvField $s.Value)`t$zh")
        }
        [System.IO.File]::WriteAllLines($outFile, $lines, $Utf8NoBom)
    }

    $manifest.Add([pscustomobject]@{
        assembly    = $t.Assembly
        sourceFile  = $t.File
        version     = $t.Version
        satellite   = "$($t.Assembly).resources.dll"
        groups      = $groupInfo
    })
}

if (-not $Diff) {
    New-Item -ItemType Directory -Force -Path $ReferenceDir | Out-Null
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $ReferenceDir 'manifest.json') -Encoding UTF8

    Write-Host ''
    Write-Host "提取完成:" -ForegroundColor Green
    Write-Host "  资源组    : $($totals.groups)"
    Write-Host "  字符串词条: $($totals.keys)"
    Write-Host "  非字符串条目: $($totals.nonStrings)"
    Write-Host "  保留已有译文: $($totals.kept)"
    Write-Host "  输出目录  : $TranslationsDir"
}
