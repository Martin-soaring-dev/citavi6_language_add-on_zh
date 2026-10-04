#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Citavi 6 中文语言包安装器(自动检测 Citavi / Word 加载项 → 预览 → 执行)。

.DESCRIPTION
    1. 自动检测 Citavi 6 安装目录(bin)与 Word 加载项目录(也支持手动指定)。
    2. 预览安装计划(目标路径、文件、需要关闭的进程)。
    3. 执行:检测冲突进程(Citavi/Word),弹窗提示关闭(显示名称+PID),
       然后以覆盖方式复制语言包 <Culture> 到两个目标目录。
    4. 完成后弹窗提示。

    安装到 Program Files 需要管理员权限;脚本会提示并可自动提权。

.PARAMETER CitaviBin
    手动指定 Citavi 的 bin 目录(可选,默认自动检测)。

.PARAMETER WordAddInDir
    手动指定 Word 加载项目录(可选,默认自动检测)。

.PARAMETER SourceDir
    语言包源目录(默认:脚本同级的 zh\ ,或仓库 dist\zh)。

.PARAMETER Culture
    语言目录名,默认 zh。

.PARAMETER Uninstall
    卸载:删除目标目录下的 <Culture> 文件夹。

.PARAMETER WhatIf
    只预览计划,不执行。

.PARAMETER Yes
    跳过确认,直接执行。

.EXAMPLE
    pwsh ./Install-Toolkit.ps1
    pwsh ./Install-Toolkit.ps1 -CitaviBin "D:\Program Files (x86)\Citavi 6\bin"
    pwsh ./Install-Toolkit.ps1 -Uninstall -Yes
#>
[CmdletBinding()]
param(
    [string]$CitaviBin = '',
    [string]$WordAddInDir = '',
    [string]$SourceDir = '',
    [string]$Culture = 'zh',
    [switch]$Uninstall,
    [switch]$WhatIf,
    [switch]$Yes,
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function W([string]$m,[string]$c='Gray'){ Write-Host $m -ForegroundColor $c }
function Step([string]$m){ Write-Host ("`n=== {0} ===" -f $m) -ForegroundColor Cyan }
function MB([string]$text,[string]$title,[string]$buttons='OK',[string]$icon='Information'){
    if ($NoGui) {
        Write-Host ("[弹窗/{0}] {1}" -f $buttons, ($text -replace "`n",' ')) -ForegroundColor DarkYellow
        if ($buttons -in @('YesNo','Question')) { return [System.Windows.Forms.DialogResult]::Yes }
        return [System.Windows.Forms.DialogResult]::OK
    }
    return [System.Windows.Forms.MessageBox]::Show($text,$title,
        [System.Windows.Forms.MessageBoxButtons]::$buttons,
        [System.Windows.Forms.MessageBoxIcon]::$icon)
}
function Test-Admin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}
function Get-StartupSettingsFile { Join-Path $env:APPDATA 'Swiss Academic Software\StartupSettings6.xml' }

# ---------- 源目录 ----------
function Resolve-SourceDir {
    if ($SourceDir) { return (Resolve-Path $SourceDir).Path }
    $cands = @(
        (Join-Path $PSScriptRoot $Culture),
        (Join-Path (Split-Path -Parent $PSScriptRoot) "dist\$Culture")
    )
    foreach ($c in $cands) { if (Test-Path (Join-Path $c 'SwissAcademic.Resources.resources.dll')) { return (Resolve-Path $c).Path } }
    return $null
}

# ---------- Citavi 检测 ----------
function Test-CitaviBin([string]$p){ return ($p -and (Test-Path (Join-Path $p 'Citavi.exe')) -and (Test-Path (Join-Path $p 'SwissAcademic.dll'))) }
function Get-CitaviCandidates {
    $l = [System.Collections.Generic.List[string]]::new()
    foreach ($k in 'HKCU:\SOFTWARE\Swiss Academic Software\Citavi 6','HKLM:\SOFTWARE\WOW6432Node\Swiss Academic Software\Citavi 6','HKLM:\SOFTWARE\Swiss Academic Software\Citavi 6') {
        try { $v = (Get-ItemProperty $k -ErrorAction Stop).Path; if ($v) { $l.Add((Split-Path $v -Parent)) } } catch {}
    }
    foreach ($root in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -match 'Citavi 6' -and $p.InstallLocation) { $l.Add((Join-Path $p.InstallLocation 'bin')) }
        }
    }
    $ss = Get-StartupSettingsFile
    if (Test-Path $ss) {
        try { [xml]$x = Get-Content $ss -Raw; foreach ($s in $x.StartupSettings.StartupPathSet) { if ($s.ApplicationFolder) { $l.Add($s.ApplicationFolder) } } } catch {}
    }
    $l.Add('C:\Program Files (x86)\Citavi 6\bin'); $l.Add('C:\Program Files\Citavi 6\bin')
    return ($l | Select-Object -Unique)
}
function Resolve-CitaviBin {
    if ($CitaviBin) { if (Test-CitaviBin $CitaviBin) { return (Resolve-Path $CitaviBin).Path } else { throw "指定的 Citavi bin 无效(缺 Citavi.exe / SwissAcademic.dll):$CitaviBin" } }
    foreach ($c in Get-CitaviCandidates) { if (Test-CitaviBin $c) { return (Resolve-Path $c).Path } }
    return $null
}

# ---------- Word 加载项检测 ----------
function Test-WordAddInDir([string]$p){ return ($p -and (Test-Path (Join-Path $p 'SwissAcademic.Citavi.WordAddIn.dll'))) }
function Get-WordAddInCandidates {
    $l = [System.Collections.Generic.List[string]]::new()
    $ss = Get-StartupSettingsFile
    if (Test-Path $ss) {
        try { [xml]$x = Get-Content $ss -Raw; foreach ($s in $x.StartupSettings.StartupPathSet) { if ($s.ApplicationFolder -match 'Citavi Word AddIn') { $l.Add($s.ApplicationFolder) } } } catch {}
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $root = Join-Path $base 'Microsoft Office\Root'
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Join-Path $_.FullName 'ADDINS\Citavi Word AddIn'; if (Test-Path $p) { $l.Add($p) }
        }
    }
    # 注册表 Office 加载项(尽力而为)
    foreach ($rk in 'HKCU:\Software\Microsoft\Office\Word\Addins','HKLM:\SOFTWARE\Microsoft\Office\Word\Addins') {
        Get-ChildItem $rk -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            $blob = "$($p.FriendlyName) $($p.Description) $($p.Manifest)"
            if ($blob -match 'Citavi') {
                $m = [regex]::Match($blob, '[A-Za-z]:\\[^"]*Citavi Word AddIn')
                if ($m.Success) { $l.Add($m.Value) }
            }
        }
    }
    return ($l | Select-Object -Unique)
}
function Resolve-WordAddInDir {
    if ($WordAddInDir) { if (Test-WordAddInDir $WordAddInDir) { return (Resolve-Path $WordAddInDir).Path } else { throw "指定的 Word 加载项目录无效(缺 SwissAcademic.Citavi.WordAddIn.dll):$WordAddInDir" } }
    foreach ($c in Get-WordAddInCandidates) { if (Test-WordAddInDir $c) { return (Resolve-Path $c).Path } }
    return $null
}

# ---------- 冲突进程 ----------
function Get-Running([string[]]$names){ return @(Get-Process -Name $names -ErrorAction SilentlyContinue) }
function Wait-ProcessesClosed([string[]]$names, [string]$reason) {
    $procs = Get-Running $names
    while ($procs.Count -gt 0) {
        $lines = ($procs | ForEach-Object { "  • $($_.ProcessName)    PID $($_.Id)" }) -join "`n"
        $r = MB ("需要先关闭以下进程才能继续:`n`n$lines`n`n原因:$reason`n`n关闭后点「确定」继续;点「取消」放弃本次操作。") 'Citavi 中文语言包 - 请关闭相关进程' 'OKCancel' 'Warning'
        if ($r -eq [System.Windows.Forms.DialogResult]::Cancel) { return $false }
        Start-Sleep -Seconds 1
        $procs = Get-Running $names
    }
    return $true
}

# ================= 主流程 =================
try {
    Write-Host "Citavi 6 中文语言包安装器 (v0.102)" -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor DarkGray

    $src = Resolve-SourceDir
    if (-not $src) { MB "找不到语言包源目录(zh)。请把本安装器与 zh 文件夹放在一起。" '错误' 'OK' 'Error'; exit 1 }

    # 检测
    Step "1/4 检测安装"
    $cit = $null; try { $cit = Resolve-CitaviBin } catch { W "  $_" 'Yellow' }
    $wa  = $null; try { $wa  = Resolve-WordAddInDir } catch { W "  $_" 'Yellow' }
    W ("  Citavi bin        : " + $(if($cit){$cit}else{'未检测到(可用 -CitaviBin 指定)'}))
    W ("  Word 加载项目录   : " + $(if($wa){$wa}else{'未检测到(可用 -WordAddInDir 指定;无则跳过)'}))
    W ("  语言包源          : $src")

    # 预览
    Step "2/4 预览计划"
    $targets = [System.Collections.Generic.List[object]]::new()
    if ($cit) { $targets.Add([pscustomobject]@{ Kind='Citavi bin'; Dir=(Join-Path $cit $Culture); Proc=@('Citavi') }) }
    if ($wa)  { $targets.Add([pscustomobject]@{ Kind='Word 加载项'; Dir=(Join-Path $wa  $Culture); Proc=@('WINWORD') }) }
    if ($targets.Count -eq 0) { MB "未检测到任何可安装目标。`n请确认已安装 Citavi 6,或用 -CitaviBin / -WordAddInDir 手动指定。" '无可安装目标' 'OK' 'Warning'; exit 1 }
    $files = @(Get-ChildItem $src -Filter *.dll)
    foreach ($t in $targets) {
        $exist = Test-Path $t.Dir
        W ("  · {0,-10} -> {1}   [{2}]" -f $t.Kind, $t.Dir, $(if($exist){'将覆盖'}else{'新建'}))
    }
    W ("  将复制 {0} 个 DLL;模式:覆盖" -f $files.Count)
    $allProc = @(); foreach ($t in $targets) { $allProc += $t.Proc }; $allProc = @($allProc | Select-Object -Unique)
    $running = Get-Running $allProc
    if ($running) { W ("  需关闭进程: " + (($running | ForEach-Object { "$($_.ProcessName)(PID $($_.Id))" }) -join ', ')) 'Yellow' } else { W "  需关闭进程: 无(可直接安装)" 'Green' }

    if ($WhatIf) { MB "预览完成(未执行)。" 'Citavi 中文语言包 - 预览' 'OK' 'Information'; exit 0 }

    if (-not $Yes) {
        if ((MB "即将按上述计划安装。是否继续?" 'Citavi 中文语言包 - 确认' 'YesNo' 'Question') -ne [System.Windows.Forms.DialogResult]::Yes) { W "已取消。"; exit 0 }
    }

    # 提权
    if ((-not (Test-Admin)) -and ($targets | Where-Object { $_.Dir -match 'Program Files|\\ADDINS\\' })) {
        if ((MB "安装到 Program Files 需要管理员权限。是否以管理员身份重新运行?" '需要提权' 'YesNo' 'Warning') -eq [System.Windows.Forms.DialogResult]::Yes) {
            $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Culture `"$Culture`" -SourceDir `"$src`" -Yes"
            if ($CitaviBin) { $arg += " -CitaviBin `"$CitaviBin`"" }
            if ($WordAddInDir) { $arg += " -WordAddInDir `"$WordAddInDir`"" }
            if ($Uninstall) { $arg += " -Uninstall" }
            Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $arg
            exit 0
        }
    }

    # 执行
    Step "3/4 执行"
    if ($Uninstall) {
        foreach ($t in $targets) {
            if (-not (Wait-ProcessesClosed $t.Proc "卸载 $($t.Kind) 语言包")) { exit 1 }
            if (Test-Path $t.Dir) { Remove-Item $t.Dir -Recurse -Force; W "  已删除 $($t.Dir)" 'Green' } else { W "  跳过(不存在): $($t.Dir)" 'DarkGray' }
        }
    } else {
        foreach ($t in $targets) {
            if (-not (Wait-ProcessesClosed $t.Proc "写入 $($t.Kind)(文件可能被占用)")) { exit 1 }
            if (Test-Path $t.Dir) { Remove-Item $t.Dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $t.Dir | Out-Null
            Copy-Item (Join-Path $src '*.dll') $t.Dir -Force
            $n = @(Get-ChildItem $t.Dir -Filter *.dll).Count
            W ("  已安装 {0} 个文件到 {1}" -f $n, $t.Dir) 'Green'
        }
    }

    Step "4/4 完成"
    $done = if ($Uninstall) { "卸载完成。" } else { "安装完成。`n`n下一步:打开 Citavi → 工具 → 语言 → 选择「中文」;如装了 Word 加载项,请重启 Word。" }
    W $done 'Green'
    MB $done 'Citavi 中文语言包' 'OK' 'Information'
    exit 0
}
catch {
    W "错误: $($_.Exception.Message)" 'Red'
    MB ("发生错误:`n`n$($_.Exception.Message)") 'Citavi 中文语言包 - 错误' 'OK' 'Error'
    exit 1
}