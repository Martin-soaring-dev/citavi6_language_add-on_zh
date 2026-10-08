#!/usr/bin/env pwsh
<#
.SYNOPSIS
    把品牌 SVG 光栅化为 Windows 安装包所需的位图资产。

.DESCRIPTION
    源文件:
      docs/brand/simple/svg/icon-light.svg     → setup.ico(16/24/32/48/64/128/256,PNG 帧)
      docs/brand/simple/svg/logo-symbol.svg    → wizard-image.png(656x1256,透明底)
                                                 wizard-small.png(318x318,透明底)
                                                 logo-symbol.png(456x295,透明底,图形安装器头部)

    产物提交进仓库,所以 CI(只装 Inno Setup)不需要任何光栅器;改过 SVG 后重跑本脚本即可。
    依赖本机任一 headless Chromium(Chrome / Edge / ms-playwright 的 chromium 或 headless shell)
    与 .NET 的 System.Drawing(Windows 自带),不引入 npm / pip 依赖。
    中间页面与浏览器配置档写到 build/brand/(已被 .gitignore 忽略)。

    画布摆放规则(向导图为竖长条,Inno 强制 164:314 比例):
      wizard-image 内容区取画布宽度的 78%,垂直中心放在画布 42% 高度处;
      wizard-small 内容区取画布宽度的 86%,水平垂直均居中。
    两张图都不放文字:100% DPI 下向导区只有 202px 宽,文字必糊,且规范指定
    的衬线字体不保证在构建机上存在。

.PARAMETER Renderer
    auto(默认)按 Chrome → Edge → ms-playwright 顺序探测;也可手动指定。

.EXAMPLE
    pwsh ./tools/Build-BrandAssets.ps1
    pwsh ./tools/Build-BrandAssets.ps1 -Renderer edge
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot),

    [ValidateSet('auto', 'chrome', 'edge', 'playwright')]
    [string]$Renderer = 'auto'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$SvgDir  = Join-Path $RepoDir 'docs\brand\simple\svg'
$OutDir  = Join-Path $RepoDir 'docs\brand\simple\export\win'
$Stage   = Join-Path $RepoDir 'build\brand'

$IconSource   = Join-Path $SvgDir 'icon-light.svg'
$SymbolSource = Join-Path $SvgDir 'logo-symbol.svg'

# wizard-image 画布宽度:必须是 164 的整数倍,才能精确保持 Inno 要求的 164:314 比例。
$WizardCanvasWidth   = 656
$WizardFill          = 0.78
$WizardVerticalRatio = 0.42

$SmallCanvasWidth = 318
$SmallFill        = 0.86

$LogoWidth = 456

$IconSizes = @(16, 24, 32, 48, 64, 128, 256)

foreach ($f in @($IconSource, $SymbolSource)) {
    if (-not (Test-Path $f)) { throw "找不到品牌 SVG: $f" }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

# ---------- 浏览器探测 ----------
function Find-Chromium([string]$Preference) {
    $cands = @()
    if ($Preference -in 'auto', 'chrome') {
        $cands += @(
            (Join-Path ${env:ProgramFiles}     'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA        'Google\Chrome\Application\chrome.exe')
        ) | ForEach-Object { [pscustomobject]@{ Exe = $_; Kind = 'browser' } }
    }
    if ($Preference -in 'auto', 'edge') {
        $cands += @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path ${env:ProgramFiles}      'Microsoft\Edge\Application\msedge.exe')
        ) | ForEach-Object { [pscustomobject]@{ Exe = $_; Kind = 'browser' } }
    }
    if ($Preference -in 'auto', 'playwright') {
        $root = Join-Path $env:LOCALAPPDATA 'ms-playwright'
        if (Test-Path $root) {
            $cands += @(Get-ChildItem $root -Directory -Filter 'chromium*' -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ChildItem $_.FullName -Recurse -Filter 'chrome*.exe' -ErrorAction SilentlyContinue } |
                Where-Object { $_.Name -match '^(chrome|chrome-headless-shell)\.exe$' } |
                ForEach-Object { [pscustomobject]@{
                    Exe  = $_.FullName
                    Kind = $(if ($_.Name -eq 'chrome-headless-shell.exe') { 'shell' } else { 'browser' })
                } })
        }
    }
    foreach ($c in $cands) {
        if ($c.Exe -and (Test-Path $c.Exe)) {
            return [pscustomobject]@{
                Exe  = (Get-Item $c.Exe).FullName
                Kind = $c.Kind
            }
        }
    }
    return $null
}

$browser = Find-Chromium $Renderer
if (-not $browser) {
    throw ("未找到可用的 headless Chromium({0})。可用 -- 安装 Chrome/Edge,或指定 -Renderer。" -f $Renderer)
}
Write-Host "光栅器: $($browser.Exe)" -ForegroundColor Cyan

# ---------- SVG 固有尺寸 ----------
function Get-SvgSize([string]$Path) {
    $t = Get-Content -Raw -Path $Path
    $w = [regex]::Match($t, '<svg[^>]*\bwidth="(\d+(?:\.\d+)?)?"')
    $h = [regex]::Match($t, '<svg[^>]*\bheight="(\d+(?:\.\d+)?)?"')
    if ($w.Success -and $h.Success) {
        return [pscustomobject]@{ Width = [double]$w.Groups[1].Value; Height = [double]$h.Groups[1].Value }
    }
    $vb = [regex]::Match($t, 'viewBox="([\d.\-\s]+)"')
    if ($vb.Success) {
        $p = -split $vb.Groups[1].Value
        return [pscustomobject]@{ Width = [double]$p[2]; Height = [double]$p[3] }
    }
    throw "无法从 SVG 取尺寸: $Path"
}

$symSize  = Get-SvgSize $SymbolSource
$iconSize = Get-SvgSize $IconSource

# ---------- 合成页面 + 截图 ----------
function New-ComposePage {
    param(
        [string]$Path,
        [string]$SvgFile,
        [int]$CanvasWidth, [int]$CanvasHeight,
        [int]$BoxLeft, [int]$BoxTop, [int]$BoxWidth, [int]$BoxHeight
    )
    $url = 'file:///' + ($SvgFile -replace '\\', '/')
@"
<!doctype html>
<html><head><meta charset="utf-8">
<style>
  html, body { margin: 0; padding: 0; width: ${CanvasWidth}px; height: ${CanvasHeight}px;
               background: transparent; overflow: hidden; }
  img { position: absolute; display: block; left: ${BoxLeft}px; top: ${BoxTop}px;
        width: ${BoxWidth}px; height: ${BoxHeight}px; }
</style></head>
<body><img src="$url" alt=""></body></html>
"@ | Set-Content -Path $Path -Encoding UTF8
}

function Invoke-Snapshot {
    param(
        [string]$PageFile,
        [string]$PngFile,
        [int]$Width,
        [int]$Height
    )
    $profileDir = Join-Path $Stage ('profile-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $argList = @(
        '--disable-gpu',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-extensions',
        '--disable-background-networking',
        '--hide-scrollbars',
        '--force-device-scale-factor=1',
        '--default-background-color=00000000',
        "--user-data-dir=$profileDir",
        "--window-size=$Width,$Height",
        "--screenshot=$PngFile",
        $PageFile
    )
    if ($browser.Kind -ne 'shell') { $argList = @('--headless=new') + $argList }
    $line = ($argList | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '

    if (Test-Path $PngFile) { Remove-Item $PngFile -Force }
    # Chrome 会向 stderr 打印无害的 network notifier 噪声,导到暂存目录保持构建输出干净。
    $stdoutLog = Join-Path $Stage 'chrome-out.log'
    $stderrLog = Join-Path $Stage 'chrome-err.log'
    $proc = Start-Process -FilePath $browser.Exe -ArgumentList $line -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    if (-not $proc.WaitForExit(120000)) {
        try { $proc.Kill() } catch { }
        throw "Chromium 截图超时: $PngFile"
    }
    if (-not (Test-Path $PngFile)) {
        $err = if (Test-Path $stderrLog) { (Get-Content -Raw $stderrLog) } else { '' }
        throw "Chromium 未写出截图: $PngFile`n$err"
    }
    return (Get-Item $PngFile)
}

function Assert-PngSize {
    param([string]$Path, [int]$ExpectWidth, [int]$ExpectHeight)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 26 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80) { throw "不是 PNG 文件: $Path" }
    $w = [int](($bytes[16] * 16777216) + ($bytes[17] * 65536) + ($bytes[18] * 256) + $bytes[19])
    $h = [int](($bytes[20] * 16777216) + ($bytes[21] * 65536) + ($bytes[22] * 256) + $bytes[23])
    if ($w -ne $ExpectWidth -or $h -ne $ExpectHeight) {
        throw ("截图尺寸不符: $Path 实际 ${w}x${h},期望 ${ExpectWidth}x${ExpectHeight}")
    }
    if ($bytes[25] -ne 6) { throw "截图不是 RGBA(无透明通道): $Path" }
}

function Test-CornersTransparent {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $fs = [IO.File]::OpenRead($Path)
    try {
        $bmp = New-Object System.Drawing.Bitmap($fs)
        try {
            $w = $bmp.Width
            $h = $bmp.Height
            $corners = @(@(0, 0), @(($w - 1), 0), @(0, ($h - 1)), @(($w - 1), ($h - 1)))
            foreach ($pt in $corners) {
                $x = [int]$pt[0]
                $y = [int]$pt[1]
                if ($bmp.GetPixel($x, $y).A -ne 0) {
                    throw ("四角不是透明像素: $Path 位置 $x,$y")
                }
            }
        } finally { $bmp.Dispose() }
    } finally { $fs.Dispose() }
}

function New-FitmapFromPng {
    param([string]$Path, [int]$Size)
    $src = [IO.File]::ReadAllBytes($Path)
    $in  = New-Object IO.MemoryStream(, $src)
    try {
        $img = [System.Drawing.Image]::FromStream($in)
        try {
            $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.CompositingMode   = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                $g.Clear([System.Drawing.Color]::Transparent)
                $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
                $g.DrawImage($img, $rect)
            } finally { $g.Dispose() }
            $out = New-Object IO.MemoryStream
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            # 前置逗号阻止 PowerShell 把 byte[] 摊平成 Object[]:
            # 一旦变成 Object[],BinaryWriter.Write 会绑定 Write(byte) 重载,只写 1 个字节。
            return , $out.ToArray()
        } finally { $img.Dispose() }
    } finally { $in.Dispose() }
}

function New-IcoFile {
    param([object[]]$Frames, [string]$OutPath)
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter($ms)
    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]$Frames.Count)
    $offset = 6 + 16 * $Frames.Count
    foreach ($f in $Frames) {
        $dim = if ($f.Size -ge 256) { 0 } else { $f.Size }
        $bw.Write([Byte]$dim)
        $bw.Write([Byte]$dim)
        $bw.Write([Byte]0)
        $bw.Write([Byte]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]32)
        $bw.Write([UInt32]$f.Png.Length)
        $bw.Write([UInt32]$offset)
        $offset += $f.Png.Length
    }
    foreach ($f in $Frames) { $bw.Write([byte[]]$f.Png) }
    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()

    # 自校验:容器长度必须等于「目录 + 各帧」之和,否则说明帧数据被 PowerShell 摊平过。
    $frameTotal = [long](($Frames | ForEach-Object { [long]$_.Png.Length } | Measure-Object -Sum).Sum)
    $expected = 6 + 16 * $Frames.Count + $frameTotal
    [IO.File]::WriteAllBytes($OutPath, $bytes)
    $actual = (Get-Item $OutPath).Length
    if ($actual -ne $expected) {
        throw ("ICO 容器不完整: {0} 实际 {1} 字节,期望 {2} 字节" -f $OutPath, $actual, $expected)
    }
    return $actual
}

# ---------- 1) setup.ico ----------
Write-Host '== 生成 setup.ico ==' -ForegroundColor Cyan
$iconRender = 1024
$iconPage = Join-Path $Stage 'icon.html'
$iconPng  = Join-Path $Stage 'icon-1024.png'
New-ComposePage -Path $iconPage -SvgFile $IconSource `
    -CanvasWidth $iconRender -CanvasHeight $iconRender `
    -BoxLeft 0 -BoxTop 0 -BoxWidth $iconRender -BoxHeight $iconRender
Invoke-Snapshot -PageFile $iconPage -PngFile $iconPng -Width $iconRender -Height $iconRender | Out-Null
Assert-PngSize -Path $iconPng -ExpectWidth $iconRender -ExpectHeight $iconRender

$frames = @()
foreach ($s in $IconSizes) {
    $frames += [pscustomobject]@{ Size = $s; Png = [byte[]](New-FitmapFromPng -Path $iconPng -Size $s) }
}
$icoPath = Join-Path $OutDir 'setup.ico'
$icoBytes = New-IcoFile -Frames $frames -OutPath $icoPath
Write-Host ("已写出 {0}({1} 字节;帧: {2})" -f $icoPath, $icoBytes, ($IconSizes -join '/'))

# ---------- 2) wizard-image.png(欢迎页 + 完成页左侧大图) ----------
Write-Host '== 生成 wizard-image.png ==' -ForegroundColor Cyan
$wizardW = $WizardCanvasWidth
$wizardH = [int][Math]::Round($wizardW * 314 / 164)                       # Inno 固定 164:314
$contentW = [int][Math]::Round($wizardW * $WizardFill)
$contentH = [int][Math]::Round($contentW * $symSize.Height / $symSize.Width)
$boxLeft  = [int][Math]::Round(($wizardW - $contentW) / 2)
$boxTop   = [int][Math]::Round(($wizardH - $contentH) * $WizardVerticalRatio)
$wizardPng = Join-Path $OutDir 'wizard-image.png'
$wizardPage = Join-Path $Stage 'wizard-image.html'
New-ComposePage -Path $wizardPage -SvgFile $SymbolSource `
    -CanvasWidth $wizardW -CanvasHeight $wizardH `
    -BoxLeft $boxLeft -BoxTop $boxTop -BoxWidth $contentW -BoxHeight $contentH
Invoke-Snapshot -PageFile $wizardPage -PngFile $wizardPng -Width $wizardW -Height $wizardH | Out-Null
Assert-PngSize -Path $wizardPng -ExpectWidth $wizardW -ExpectHeight $wizardH
Test-CornersTransparent -Path $wizardPng
Write-Host ("画布 {0}x{1};符号内容区 {2}x{3} @({4},{5})" -f $wizardW, $wizardH, $contentW, $contentH, $boxLeft, $boxTop)

# ---------- 3) wizard-small.png(内页右上角方图) ----------
Write-Host '== 生成 wizard-small.png ==' -ForegroundColor Cyan
$smallW = $SmallCanvasWidth
$smallH = $SmallCanvasWidth
$sContentW = [int][Math]::Round($smallW * $SmallFill)
$sContentH = [int][Math]::Round($sContentW * $symSize.Height / $symSize.Width)
$sLeft = [int][Math]::Round(($smallW - $sContentW) / 2)
$sTop  = [int][Math]::Round(($smallH - $sContentH) / 2)
$smallPng = Join-Path $OutDir 'wizard-small.png'
$smallPage = Join-Path $Stage 'wizard-small.html'
New-ComposePage -Path $smallPage -SvgFile $SymbolSource `
    -CanvasWidth $smallW -CanvasHeight $smallH `
    -BoxLeft $sLeft -BoxTop $sTop -BoxWidth $sContentW -BoxHeight $sContentH
Invoke-Snapshot -PageFile $smallPage -PngFile $smallPng -Width $smallW -Height $smallH | Out-Null
Assert-PngSize -Path $smallPng -ExpectWidth $smallW -ExpectHeight $smallH
Test-CornersTransparent -Path $smallPng
Write-Host ("画布 {0}x{1};符号内容区 {2}x{3} @({4},{5})" -f $smallW, $smallH, $sContentW, $sContentH, $sLeft, $sTop)

# ---------- 4) logo-symbol.png(横版紧裁符号,供 ZIP 里的图形安装器头部使用) ----------
Write-Host '== 生成 logo-symbol.png ==' -ForegroundColor Cyan
# 头部实际显示约 68x44,按符号固有比例的一半光栅化即可(矢量渲染,不存在缩放损失),
# 全尺寸 911x590 的 PNG 会到 220 KB 且没有透明区可压缩。
$logoW = $LogoWidth
$logoH = [int][Math]::Round($logoW * $symSize.Height / $symSize.Width)
$logoPng = Join-Path $OutDir 'logo-symbol.png'
$logoPage = Join-Path $Stage 'logo-symbol.html'
New-ComposePage -Path $logoPage -SvgFile $SymbolSource `
    -CanvasWidth $logoW -CanvasHeight $logoH `
    -BoxLeft 0 -BoxTop 0 -BoxWidth $logoW -BoxHeight $logoH
Invoke-Snapshot -PageFile $logoPage -PngFile $logoPng -Width $logoW -Height $logoH | Out-Null
Assert-PngSize -Path $logoPng -ExpectWidth $logoW -ExpectHeight $logoH
Test-CornersTransparent -Path $logoPng
Write-Host ("画布 {0}x{1}(按符号固有比例)" -f $logoW, $logoH)

# ---------- 汇总 ----------
Write-Host ''
Write-Host '== 产物 ==' -ForegroundColor Green
Get-ChildItem $OutDir -File | ForEach-Object {
    [pscustomobject]@{
        文件   = $_.Name
        'KB'   = [Math]::Round($_.Length / 1KB, 1)
        更新时间 = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
} | Format-Table -AutoSize

Write-Host ("图标源 SVG 尺寸: {0}x{1};符号源 SVG 尺寸: {2}x{3}" -f $iconSize.Width, $iconSize.Height, $symSize.Width, $symSize.Height)
Write-Host '下一步: pwsh ./tools/Build-Installer.ps1 -Version <版本>'
