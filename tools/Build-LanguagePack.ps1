#!/usr/bin/env pwsh
<#
.SYNOPSIS
    把 translations/*.tsv 编译为 Citavi 6 的附属程序集,输出到 dist/<Culture>/。

.DESCRIPTION
    1. 读取 translations/<Assembly>/*.tsv(UTF-8 无 BOM,Tab 分隔)。
    2. 对每个资源组生成 <baseName>.<Culture>.resources
       (中文为空的 key 省略 -> 运行时自动回退英文)。
    3. 还原 reference/nonstring/ 下的非字符串条目。
    4. 生成 AssemblyInfo.cs(AssemblyVersion + AssemblyCulture)。
    5. 用 csc.exe 编译出 6 个 <Assembly>.resources.dll 到 dist/<Culture>/。

    版本号取自 reference/manifest.json(由 Extract 生成),缺失时使用内置表。

.PARAMETER Culture
    语言目录名,默认 zh。注意:不可用 zh-Hans(Citavi 的目录名正则不接受)。

.EXAMPLE
    pwsh ./tools/Build-LanguagePack.ps1
#>
[CmdletBinding()]
param(
    [string]$Culture = 'zh',

    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [string]$TranslationsDir = '',

    [string]$ReferenceDir = '',

    [string]$OutDir = '',

    [string]$BuildDir = '',

    [string]$Csc = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($TranslationsDir)) { $TranslationsDir = Join-Path $RepoDir 'translations' }
if ([string]::IsNullOrEmpty($ReferenceDir))    { $ReferenceDir    = Join-Path $RepoDir 'reference' }
if ([string]::IsNullOrEmpty($OutDir))          { $OutDir          = Join-Path $RepoDir 'dist' }
if ([string]::IsNullOrEmpty($BuildDir))        { $BuildDir        = Join-Path $RepoDir 'build' }
if ([string]::IsNullOrEmpty($Csc))             { $Csc             = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe' }

if (-not (Test-Path $Csc)) { throw "找不到 csc.exe:$Csc" }

# 内置版本表(与 docs/01-mechanism.md §8 一致);reference/manifest.json 可覆盖
$VersionTable = @{
    'Citavi'                        = '5.8.0.0'
    'SwissAcademic'                 = '5.8.0.0'
    'SwissAcademic.Citavi'          = '5.8.0.0'
    'SwissAcademic.Citavi.WordAddIn'= '1.0.0.0'
    'SwissAcademic.Controls'        = '5.8.0.0'
    'SwissAcademic.WordProcessing'  = '5.8.0.0'
    'SwissAcademic.Resources'       = '6.0.0.0'
}

$manifestPath = Join-Path $ReferenceDir 'manifest.json'
if (Test-Path $manifestPath) {
    try {
        $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
        foreach ($a in $m) { if ($a.assembly -and $a.version) { $VersionTable[$a.assembly] = $a.version } }
        Write-Host "使用 reference/manifest.json 中的版本信息。"
    } catch { Write-Warning "无法读取 manifest.json,使用内置版本表。" }
}

$CultureDir = Join-Path $OutDir $Culture
$BuildRoot  = Join-Path $BuildDir "satellite-$Culture"

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

if (Test-Path $CultureDir) { Remove-Item $CultureDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $CultureDir | Out-Null
if (Test-Path $BuildRoot)  { Remove-Item $BuildRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

$summary = [System.Collections.Generic.List[object]]::new()

foreach ($assembly in ($VersionTable.Keys | Sort-Object)) {
    $srcDir  = Join-Path $TranslationsDir $assembly
    $resDir  = Join-Path $BuildRoot $assembly
    $nsDir   = Join-Path $ReferenceDir 'nonstring' $assembly
    New-Item -ItemType Directory -Force -Path $resDir | Out-Null

    $resourceArgs = [System.Collections.Generic.List[string]]::new()
    $translatedKeys = 0
    $groupCount = 0

    if (Test-Path $srcDir) {
        foreach ($tsv in (Get-ChildItem $srcDir -Filter *.tsv | Sort-Object Name)) {
            $baseName = $tsv.BaseName                 # 已是资源基名(无 .resources 后缀)
            $resName  = "$baseName.$Culture.resources" # 附属程序集内的资源名

            $entries = [ordered]@{}

            # 非字符串条目
            $nsFile = Join-Path $nsDir "$baseName.tsv"
            if (Test-Path $nsFile) {
                foreach ($line in [System.IO.File]::ReadAllLines($nsFile)) {
                    if ([string]::IsNullOrEmpty($line)) { continue }
                    $p = $line -split "`t"
                    if ($p.Count -lt 3) { continue }
                    $type = [Type]::GetType("System.$($p[1])")
                    if (-not $type) { Write-Warning "未知类型 $($p[1]) ($baseName :: $($p[0]))"; continue }
                    $val = if ($type -eq [datetime]) { [datetime]::Parse($p[2], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
                           else { [Convert]::ChangeType($p[2], $type, [Globalization.CultureInfo]::InvariantCulture) }
                    $entries[$p[0]] = $val
                }
            }

            # 字符串条目:只写有译文的
            $hasTranslation = $false
            foreach ($line in [System.IO.File]::ReadAllLines($tsv.FullName)) {
                if ([string]::IsNullOrEmpty($line)) { continue }
                $p = $line -split "`t"
                if ($p.Count -lt 3) { continue }
                $zh = ConvertFrom-TsvField $p[2]
                if ([string]::IsNullOrEmpty($zh)) { continue }
                $entries[$p[0]] = $zh
                $hasTranslation = $true
            }

            if ($entries.Count -eq 0) { continue }

            $resFile = Join-Path $resDir "$resName"
            $writer = New-Object System.Resources.ResourceWriter($resFile)
            try {
                foreach ($k in $entries.Keys) { $writer.AddResource($k, $entries[$k]) }
                $writer.Generate()
            }
            finally { $writer.Dispose() }

            $resourceArgs.Add("/resource:$resFile,$resName")
            $groupCount++
            if ($hasTranslation) { $translatedKeys += @($entries.Keys).Count }
        }
    } else {
        Write-Warning "translations/$assembly 不存在(该程序集的语言包将为空)。"
    }

    # AssemblyInfo
    $infoFile = Join-Path $resDir 'AssemblyInfo.cs'
    @(
        'using System.Reflection;',
        "[assembly: AssemblyVersion(`"$($VersionTable[$assembly])`")]",
        "[assembly: AssemblyCulture(`"$Culture`")]"
    ) | Set-Content -Path $infoFile -Encoding UTF8

    $outFile = Join-Path $CultureDir "$assembly.resources.dll"
    $cscArgs = @('/nologo', '/noconfig', '/target:library', '/optimize+', "/out:$outFile")
    $cscArgs += $resourceArgs
    $cscArgs += $infoFile

    Write-Host "编译 $assembly.resources.dll (资源组 $groupCount) ..." -NoNewline
    $log = & $Csc @cscArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host " 失败" -ForegroundColor Red
        $log | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        throw "csc 编译失败:$assembly"
    }
    Write-Host " 完成" -ForegroundColor Green

    $summary.Add([pscustomobject]@{
        assembly     = $assembly
        file         = "$assembly.resources.dll"
        version      = $VersionTable[$assembly]
        resourceSets = $groupCount
        entries      = $translatedKeys
    })
}

# 校验:语言识别必需的 SwissAcademic.Resources.resources.dll
$required = Join-Path $CultureDir 'SwissAcademic.Resources.resources.dll'
if (-not (Test-Path $required)) { throw "缺少必需的 $required" }

Write-Host ''
Write-Host "构建完成 -> $CultureDir" -ForegroundColor Green
$summary | Format-Table -AutoSize | Out-String | Write-Host
