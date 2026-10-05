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
    [string]$CustomHelpDir = '',
    [string]$SourceDir = '',
    [string]$Culture = 'zh',
    [string]$UserProfile = '',
    [string]$UserAppData = '',
    [string]$UserDocuments = '',
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
function Get-StartupSettingsFile {
    # 不假设固定位置:先看常见位置,再主动搜索
    # 提权后可能运行在别的账户下,优先使用启动器传入的“当前用户”路径
    $appData = if ($UserAppData) { $UserAppData } else { $env:APPDATA }
    $profile = if ($UserProfile) { $UserProfile } else { $env:USERPROFILE }
    $known = Join-Path $appData 'Swiss Academic Software\StartupSettings6.xml'
    if (Test-Path $known) { return $known }
    foreach ($r in @($appData, (Join-Path $profile 'AppData\Local'), "$env:ProgramData", (Join-Path $profile 'Documents'))) {
        if ($r -and (Test-Path $r)) {
            $hit = Get-ChildItem $r -Recurse -Filter 'StartupSettings6.xml' -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

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
# 快速帮助(Custom Help)源目录与目标目录
function Resolve-HelpSourceDir {
    $cands = @(
        (Join-Path $PSScriptRoot 'custom-help'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'custom-help')
    )
    foreach ($c in $cands) { if (Test-Path $c) { return (Resolve-Path $c).Path } }
    return $null
}
function Resolve-CustomHelpDir {
    if ($CustomHelpDir) { return $CustomHelpDir }
    $ud = $null
    $ss = Get-StartupSettingsFile
    if ($ss) { try { [xml]$x = Get-Content $ss -Raw; foreach ($s in $x.StartupSettings.StartupPathSet) { if ($s.UserDataFolder) { $ud = $s.UserDataFolder; break } } } catch {} }
    if ($ud) {
        $docs = if ($UserDocuments) { $UserDocuments } else { [Environment]::GetFolderPath('MyDocuments') }
        $prof = if ($UserProfile) { $UserProfile } else { $env:USERPROFILE }
        $ud = $ud -replace '%MyDocuments%', $docs
        $ud = $ud -replace '%UserProfile%', $prof
        $ud = [Environment]::ExpandEnvironmentVariables($ud)
        $ud = $ud -replace '\\\\','\'
        return (Join-Path $ud 'Custom Help')
    }
    $docs2 = if ($UserDocuments) { $UserDocuments } else { [Environment]::GetFolderPath('MyDocuments') }
    return (Join-Path $docs2 'Citavi 6\Custom Help')
}

# ---------- Citavi 检测:注册表判定是否安装;StartupSettings6.xml 取路径 ----------
function Test-CitaviBin([string]$p){ return ($p -and (Test-Path (Join-Path $p 'Citavi.exe')) -and (Test-Path (Join-Path $p 'SwissAcademic.dll'))) }

function Get-CitaviRegistry {
    $o = [pscustomobject]@{ Installed=$false; Path=$null; Keys=@() }
    $ks = @()
    foreach ($k in 'HKCU:\SOFTWARE\Swiss Academic Software\Citavi 6','HKLM:\SOFTWARE\WOW6432Node\Swiss Academic Software\Citavi 6','HKLM:\SOFTWARE\Swiss Academic Software\Citavi 6') {
        if (Test-Path $k) { $o.Installed = $true; $ks += $k; if (-not $o.Path) { $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).Path; if ($p) { $o.Path = $p } } }
    }
    if (-not $o.Installed) {
        foreach ($root in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
            Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($p.DisplayName -match 'Citavi 6') { $o.Installed = $true; if (-not $o.Path -and $p.InstallLocation) { $o.Path = (Join-Path $p.InstallLocation 'bin\Citavi.exe') } }
            }
        }
    }
    $o.Keys = $ks
    return $o
}

function Get-StartupPaths {
    $o = [pscustomobject]@{ File=(Get-StartupSettingsFile); Bins=@(); AddIns=@(); All=@() }
    if ($o.File) {
        try {
            [xml]$x = Get-Content $o.File -Raw
            foreach ($s in $x.StartupSettings.StartupPathSet) {
                $af = $s.ApplicationFolder; if (-not $af) { continue }
                $o.All += $af
                $isCit = Test-Path (Join-Path $af 'Citavi.exe')
                $isWai = Test-Path (Join-Path $af 'SwissAcademic.Citavi.WordAddIn.dll')
                if ($isCit) { $o.Bins += $af }
                if ($isWai -and -not $isCit) { $o.AddIns += $af }
            }
        } catch {}
    }
    return $o
}

function Resolve-CitaviBin {
    if ($CitaviBin) { if (Test-CitaviBin $CitaviBin) { return (Resolve-Path $CitaviBin).Path } else { throw "指定的 Citavi bin 无效(缺 Citavi.exe / SwissAcademic.dll):$CitaviBin" } }
    # 1) StartupSettings6.xml 记录的路径
    foreach ($b in @((Get-StartupPaths).Bins)) { if (Test-CitaviBin $b) { return (Resolve-Path $b).Path } }
    # 2) 注册表 Path
    $reg = Get-CitaviRegistry
    if ($reg.Path) { $b = Split-Path $reg.Path -Parent; if (Test-CitaviBin $b) { return (Resolve-Path $b).Path } }
    # 3) 文件系统兜底
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Program Files (x86)', 'D:\Program Files (x86)')) {
        if ($base -and (Test-Path $base)) {
            $hit = Get-ChildItem $base -Recurse -Filter 'Citavi.exe' -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit -and (Test-CitaviBin $hit.DirectoryName)) { return (Resolve-Path $hit.DirectoryName).Path }
        }
    }
    # 4) 常见路径
    foreach ($c in @('C:\Program Files (x86)\Citavi 6\bin','C:\Program Files\Citavi 6\bin')) { if (Test-CitaviBin $c) { return (Resolve-Path $c).Path } }
    return $null
}

# ---------- Word 加载项检测:StartupSettings6.xml 优先;Office 约定/文件系统兜底 ----------
function Test-WordAddInDir([string]$p){ return ($p -and (Test-Path (Join-Path $p 'SwissAcademic.Citavi.WordAddIn.dll'))) }

function Resolve-WordAddInDir {
    if ($WordAddInDir) { if (Test-WordAddInDir $WordAddInDir) { return (Resolve-Path $WordAddInDir).Path } else { throw "指定的 Word 加载项目录无效(缺 SwissAcademic.Citavi.WordAddIn.dll):$WordAddInDir" } }
    $cands = [System.Collections.Generic.List[string]]::new()
    # 1) StartupSettings6.xml 记录的路径(判别依据:目录里有加载项 DLL)
    foreach ($d in @((Get-StartupPaths).AddIns)) { $cands.Add($d) }
    # 2) Office ADDINS 约定目录
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $root = Join-Path $base 'Microsoft Office\Root'
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add((Join-Path $_.FullName 'ADDINS\Citavi Word AddIn')) }
    }
    $pref = $cands | Where-Object { (Test-WordAddInDir $_) -and ($_ -match '\\ADDINS\\') } | Select-Object -First 1
    if (-not $pref) { $pref = $cands | Where-Object { Test-WordAddInDir $_ } | Select-Object -First 1 }
    if ($pref) { return (Resolve-Path $pref).Path }
    # 3) 文件系统兜底:搜加载项 DLL(排除 Citavi bin)
    foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Microsoft\Office")) {
        if ($r -and (Test-Path $r)) {
            $hit = Get-ChildItem $r -Recurse -Filter 'SwissAcademic.Citavi.WordAddIn.dll' -Depth 7 -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch '\\Citavi 6\\bin' } | Select-Object -First 1
            if ($hit) { return (Resolve-Path $hit.DirectoryName).Path }
        }
    }
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

    # 检测:注册表判定是否安装 → StartupSettings6.xml 取路径 → 兜底/手动
    Step "1/4 检测安装"
    $reg = Get-CitaviRegistry
    W ("  注册表: Citavi 6 " + $(if($reg.Installed){'已安装'}else{'未安装'}))
    $st = Get-StartupPaths
    W ("  StartupSettings6.xml: " + $(if($st.File){$st.File}else{'未找到'}))
    $cit = $null; $wa = $null
    try { $cit = Resolve-CitaviBin } catch { W "  $_" 'Yellow' }
    if (-not $cit) {
        W "  未自动检测到 Citavi 6。" 'Yellow'
        if ($Yes) { throw "未检测到 Citavi 6(非交互模式,请用 -CitaviBin 指定)。" }
        $in = Read-Host "  请手动输入 Citavi 的 bin 目录(例如 D:\Program Files (x86)\Citavi 6\bin;直接回车=退出)"
        if (-not $in) { MB "未提供 Citavi 安装目录,已取消。" 'Citavi 中文语言包' 'OK' 'Warning'; exit 1 }
        if (Test-CitaviBin $in) { $cit = (Resolve-Path $in).Path } else { MB "目录无效(缺 Citavi.exe / SwissAcademic.dll):`n$in" '错误' 'OK' 'Error'; exit 1 }
    }
    try { $wa = Resolve-WordAddInDir } catch { W "  $_" 'Yellow' }
    if (-not $wa) {
        W "  未自动检测到 Word 加载项(可选)。" 'Yellow'
        if (-not $Yes) {
            $in = Read-Host "  如需 Word 加载项中文,请手动输入其目录(留空=跳过)"
            if ($in) { if (Test-WordAddInDir $in) { $wa = (Resolve-Path $in).Path } else { W "  目录无效,已跳过 Word 加载项。" 'Yellow' } }
        }
    }
    W ("  Citavi bin        : " + $(if($cit){$cit}else{'未检测到'}))
    W ("  Word 加载项目录   : " + $(if($wa){$wa}else{'未检测到(跳过)'}))
    W ("  语言包源          : $src")
    $helpSrc = Resolve-HelpSourceDir
    $helpDir = Resolve-CustomHelpDir
    W ("  快速帮助源        : " + $(if($helpSrc){$helpSrc}else{'未找到(跳过)'}))
    W ("  快速帮助目标      : " + $helpDir)

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
    if ($helpSrc) { $hc=@(Get-ChildItem $helpSrc -Filter *.zh.rtf).Count; W ("  · 快速帮助   -> {0}   [{1}]  ({2} 个 .zh.rtf)" -f $helpDir, $(if(Test-Path $helpDir){'将覆盖'}else{'新建'}), $hc) }
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
            if ($cit) { $arg += " -CitaviBin `"$cit`"" }
            if ($wa)  { $arg += " -WordAddInDir `"$wa`"" }
            if ($helpDir) { $arg += " -CustomHelpDir `"$helpDir`"" }
            $arg += " -UserProfile `"$env:USERPROFILE`" -UserAppData `"$env:APPDATA`" -UserDocuments `"$([Environment]::GetFolderPath('MyDocuments'))`""
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
        if (Test-Path $helpDir) { Remove-Item (Join-Path $helpDir '*.zh.rtf') -Force -ErrorAction SilentlyContinue; W "  已删除快速帮助文件:$helpDir" 'Green' }
    } else {
        foreach ($t in $targets) {
            if (-not (Wait-ProcessesClosed $t.Proc "写入 $($t.Kind)(文件可能被占用)")) { exit 1 }
            if (Test-Path $t.Dir) { Remove-Item $t.Dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $t.Dir | Out-Null
            Copy-Item (Join-Path $src '*.dll') $t.Dir -Force
            $n = @(Get-ChildItem $t.Dir -Filter *.dll).Count
            W ("  已安装 {0} 个文件到 {1}" -f $n, $t.Dir) 'Green'
        }
        if ($helpSrc) {
            New-Item -ItemType Directory -Force -Path $helpDir | Out-Null
            Copy-Item (Join-Path $helpSrc '*.zh.rtf') $helpDir -Force
            W ("  已安装 {0} 个快速帮助文件到 {1}" -f @(Get-ChildItem $helpDir -Filter *.zh.rtf).Count, $helpDir) 'Green'
        }
    }

    Step "4/4 完成"
    $done = if ($Uninstall) { "卸载完成。" } else { "安装完成。`n`n下一步:打开 Citavi → 工具 → 语言 → 选择「中文」;`n快速帮助已写入(重启 Citavi 生效);如装了 Word 加载项,请重启 Word。" }
    W $done 'Green'
    MB $done 'Citavi 中文语言包' 'OK' 'Information'
    exit 0
}
catch {
    W "错误: $($_.Exception.Message)" 'Red'
    MB ("发生错误:`n`n$($_.Exception.Message)") 'Citavi 中文语言包 - 错误' 'OK' 'Error'
    exit 1
}