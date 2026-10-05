#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Citavi 6 中文语言包图形安装器(WinForms,零依赖)。
.DESCRIPTION
    自动检测 Citavi 6 与 Word 加载项目录(注册表判定安装 → StartupSettings6.xml 取路径 → 兜底),
    可手动修改;预览后一键安装/卸载;必要时提权、提示关闭冲突进程;完成后弹窗。
.EXAMPLE
    pwsh ./Install-Gui.ps1
#>
[CmdletBinding()]
param(
    [string]$CitaviBin = '',
    [string]$WordAddInDir = '',
    [string]$CustomHelpDir = '',
    [string]$SourceDir = '',
    [string]$Culture = 'zh',
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ================= 共用函数(与 CLI 版一致) =================
function Test-Admin { try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false } }
function Get-StartupSettingsFile {
    $known = Join-Path $env:APPDATA 'Swiss Academic Software\StartupSettings6.xml'
    if (Test-Path $known) { return $known }
    foreach ($r in @($env:APPDATA, $env:LOCALAPPDATA, "$env:ProgramData", (Join-Path $env:USERPROFILE 'Documents'))) {
        if ($r -and (Test-Path $r)) { $hit = Get-ChildItem $r -Recurse -Filter 'StartupSettings6.xml' -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($hit) { return $hit.FullName } }
    }
    return $null
}
function Test-CitaviBin([string]$p){ return ($p -and (Test-Path (Join-Path $p 'Citavi.exe')) -and (Test-Path (Join-Path $p 'SwissAcademic.dll'))) }
function Get-CitaviRegistry {
    $o = [pscustomobject]@{ Installed=$false; Path=$null }
    foreach ($k in 'HKCU:\SOFTWARE\Swiss Academic Software\Citavi 6','HKLM:\SOFTWARE\WOW6432Node\Swiss Academic Software\Citavi 6','HKLM:\SOFTWARE\Swiss Academic Software\Citavi 6') {
        if (Test-Path $k) { $o.Installed = $true; if (-not $o.Path) { $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).Path; if ($p) { $o.Path = $p } } }
    }
    if (-not $o.Installed) {
        foreach ($root in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
            Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object { $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue; if ($p.DisplayName -match 'Citavi 6') { $o.Installed = $true } }
        }
    }
    return $o
}
function Get-StartupPaths {
    $o = [pscustomobject]@{ File=(Get-StartupSettingsFile); Bins=@(); AddIns=@() }
    if ($o.File) {
        try {
            [xml]$x = Get-Content $o.File -Raw
            foreach ($s in $x.StartupSettings.StartupPathSet) {
                $af = $s.ApplicationFolder; if (-not $af) { continue }
                $isCit = Test-Path (Join-Path $af 'Citavi.exe'); $isWai = Test-Path (Join-Path $af 'SwissAcademic.Citavi.WordAddIn.dll')
                if ($isCit) { $o.Bins += $af }; if ($isWai -and -not $isCit) { $o.AddIns += $af }
            }
        } catch {}
    }
    return $o
}
function Resolve-CitaviBin {
    if ($CitaviBin) { return (Resolve-Path $CitaviBin).Path }
    foreach ($b in @((Get-StartupPaths).Bins)) { if (Test-CitaviBin $b) { return (Resolve-Path $b).Path } }
    $reg = Get-CitaviRegistry; if ($reg.Path) { $b = Split-Path $reg.Path -Parent; if (Test-CitaviBin $b) { return (Resolve-Path $b).Path } }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Program Files (x86)', 'D:\Program Files (x86)')) {
        if ($base -and (Test-Path $base)) { $hit = Get-ChildItem $base -Recurse -Filter 'Citavi.exe' -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($hit -and (Test-CitaviBin $hit.DirectoryName)) { return (Resolve-Path $hit.DirectoryName).Path } }
    }
    foreach ($c in @('C:\Program Files (x86)\Citavi 6\bin','C:\Program Files\Citavi 6\bin')) { if (Test-CitaviBin $c) { return (Resolve-Path $c).Path } }
    return $null
}
function Test-WordAddInDir([string]$p){ return ($p -and (Test-Path (Join-Path $p 'SwissAcademic.Citavi.WordAddIn.dll'))) }
function Resolve-WordAddInDir {
    if ($WordAddInDir) { return (Resolve-Path $WordAddInDir).Path }
    $cands = [System.Collections.Generic.List[string]]::new()
    foreach ($d in @((Get-StartupPaths).AddIns)) { $cands.Add($d) }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        Get-ChildItem (Join-Path $base 'Microsoft Office\Root') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add((Join-Path $_.FullName 'ADDINS\Citavi Word AddIn')) }
    }
    $pref = $cands | Where-Object { (Test-WordAddInDir $_) -and ($_ -match '\\ADDINS\\') } | Select-Object -First 1
    if (-not $pref) { $pref = $cands | Where-Object { Test-WordAddInDir $_ } | Select-Object -First 1 }
    if ($pref) { return (Resolve-Path $pref).Path }
    foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Microsoft\Office")) {
        if ($r -and (Test-Path $r)) { $hit = Get-ChildItem $r -Recurse -Filter 'SwissAcademic.Citavi.WordAddIn.dll' -Depth 7 -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch '\\Citavi 6\\bin' } | Select-Object -First 1; if ($hit) { return (Resolve-Path $hit.DirectoryName).Path } }
    }
    return $null
}
function Resolve-SourceDir {
    if ($SourceDir) { return (Resolve-Path $SourceDir).Path }
    foreach ($c in @((Join-Path $PSScriptRoot $Culture), (Join-Path (Split-Path -Parent $PSScriptRoot) "dist\$Culture"))) {
        if (Test-Path (Join-Path $c 'SwissAcademic.Resources.resources.dll')) { return (Resolve-Path $c).Path }
    }
    return $null
}
function Resolve-HelpSourceDir {
    foreach ($c in @((Join-Path $PSScriptRoot 'custom-help'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'custom-help'))) { if (Test-Path $c) { return (Resolve-Path $c).Path } }
    return $null
}
function Resolve-CustomHelpDir {
    if ($CustomHelpDir) { return $CustomHelpDir }
    $ud = $null; $ss = Get-StartupSettingsFile
    if ($ss) { try { [xml]$x = Get-Content $ss -Raw; foreach ($s in $x.StartupSettings.StartupPathSet) { if ($s.UserDataFolder) { $ud = $s.UserDataFolder; break } } } catch {} }
    if ($ud) {
        $ud = $ud -replace '%MyDocuments%', [Environment]::GetFolderPath('MyDocuments')
        $ud = $ud -replace '%UserProfile%', $env:USERPROFILE
        $ud = [Environment]::ExpandEnvironmentVariables($ud)
        $ud = $ud -replace '\\\\','\'
        return (Join-Path $ud 'Custom Help')
    }
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Citavi 6\Custom Help')
}
function Get-Running([string[]]$names){ return @(Get-Process -Name $names -ErrorAction SilentlyContinue) }

# ================= 状态 =================
$script:Src = Resolve-SourceDir
$script:InstallProc = @{ 'Citavi bin' = @('Citavi'); 'Word 加载项' = @('WINWORD') }

# ================= 窗体 =================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Citavi 6 中文语言包 安装器  v0.102'
$form.Size = New-Object System.Drawing.Size(660, 604)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(660, 520)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Citavi 6 中文语言包(社区汉化)'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(14, 10); $lblTitle.Size = New-Object System.Drawing.Size(500, 28)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '自动检测安装路径(注册表判定安装 → StartupSettings6.xml 取路径);可手动修改。'
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$lblSub.Location = New-Object System.Drawing.Point(16, 40); $lblSub.Size = New-Object System.Drawing.Size(620, 18)
$form.Controls.Add($lblSub)

# 检测组
$grpDet = New-Object System.Windows.Forms.GroupBox
$grpDet.Text = '安装路径'; $grpDet.Location = New-Object System.Drawing.Point(12, 64); $grpDet.Size = New-Object System.Drawing.Size(620, 184)
$form.Controls.Add($grpDet)

$lblReg = New-Object System.Windows.Forms.Label
$lblReg.Location = New-Object System.Drawing.Point(12, 22); $lblReg.Size = New-Object System.Drawing.Size(596, 18)
$grpDet.Controls.Add($lblReg)
$lblXml = New-Object System.Windows.Forms.Label
$lblXml.Location = New-Object System.Drawing.Point(12, 42); $lblXml.Size = New-Object System.Drawing.Size(596, 18); $lblXml.ForeColor = [System.Drawing.Color]::DimGray
$grpDet.Controls.Add($lblXml)

$lblC = New-Object System.Windows.Forms.Label
$lblC.Text = 'Citavi 目录:'; $lblC.Location = New-Object System.Drawing.Point(12, 70); $lblC.Size = New-Object System.Drawing.Size(84, 20)
$grpDet.Controls.Add($lblC)
$txtCit = New-Object System.Windows.Forms.TextBox
$txtCit.Location = New-Object System.Drawing.Point(100, 68); $txtCit.Size = New-Object System.Drawing.Size(420, 22)
$grpDet.Controls.Add($txtCit)
$btnBrowseCit = New-Object System.Windows.Forms.Button
$btnBrowseCit.Text = '浏览…'; $btnBrowseCit.Location = New-Object System.Drawing.Point(528, 66); $btnBrowseCit.Size = New-Object System.Drawing.Size(72, 24)
$grpDet.Controls.Add($btnBrowseCit)

$lblW = New-Object System.Windows.Forms.Label
$lblW.Text = 'Word 加载项:'; $lblW.Location = New-Object System.Drawing.Point(12, 104); $lblW.Size = New-Object System.Drawing.Size(84, 20)
$grpDet.Controls.Add($lblW)
$txtWa = New-Object System.Windows.Forms.TextBox
$txtWa.Location = New-Object System.Drawing.Point(100, 102); $txtWa.Size = New-Object System.Drawing.Size(420, 22)
$grpDet.Controls.Add($txtWa)
$btnBrowseWa = New-Object System.Windows.Forms.Button
$btnBrowseWa.Text = '浏览…'; $btnBrowseWa.Location = New-Object System.Drawing.Point(528, 100); $btnBrowseWa.Size = New-Object System.Drawing.Size(72, 24)
$grpDet.Controls.Add($btnBrowseWa)

$lblH = New-Object System.Windows.Forms.Label
$lblH.Text = '快速帮助目录:'; $lblH.Location = New-Object System.Drawing.Point(12, 138); $lblH.Size = New-Object System.Drawing.Size(88, 20)
$grpDet.Controls.Add($lblH)
$txtHelp = New-Object System.Windows.Forms.TextBox
$txtHelp.Location = New-Object System.Drawing.Point(100, 136); $txtHelp.Size = New-Object System.Drawing.Size(420, 22)
$grpDet.Controls.Add($txtHelp)
$btnBrowseHelp = New-Object System.Windows.Forms.Button
$btnBrowseHelp.Text = '浏览…'; $btnBrowseHelp.Location = New-Object System.Drawing.Point(528, 134); $btnBrowseHelp.Size = New-Object System.Drawing.Size(72, 24)
$grpDet.Controls.Add($btnBrowseHelp)

# 日志组
$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = '预览 / 日志'; $grpLog.Location = New-Object System.Drawing.Point(12, 256); $grpLog.Size = New-Object System.Drawing.Size(620, 246)
$form.Controls.Add($grpLog)
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(12, 22); $txtLog.Size = New-Object System.Drawing.Size(596, 184)
$txtLog.BackColor = [System.Drawing.Color]::White; $txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$grpLog.Controls.Add($txtLog)
$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(12, 214); $bar.Size = New-Object System.Drawing.Size(596, 18)
$grpLog.Controls.Add($bar)

# 按钮
$btnDetect = New-Object System.Windows.Forms.Button
$btnDetect.Text = '重新检测'; $btnDetect.Location = New-Object System.Drawing.Point(12, 516); $btnDetect.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnDetect)
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = '安装'; $btnInstall.Location = New-Object System.Drawing.Point(424, 516); $btnInstall.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnInstall)
$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = '卸载'; $btnUninstall.Location = New-Object System.Drawing.Point(524, 516); $btnUninstall.Size = New-Object System.Drawing.Size(72, 30)
$form.Controls.Add($btnUninstall)
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = '退出'; $btnExit.Location = New-Object System.Drawing.Point(600, 516); $btnExit.Size = New-Object System.Drawing.Size(32, 30); $btnExit.Visible = $false
$form.Controls.Add($btnExit)
$form.CancelButton = $btnExit

function Log([string]$m){ $txtLog.AppendText($m + "`r`n"); $txtLog.SelectionStart = $txtLog.TextLength; $txtLog.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() }
function Info($t,$c='Information'){ return [System.Windows.Forms.MessageBox]::Show($t,'Citavi 中文语言包',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::$c) }

function DoDetect {
    $txtLog.Clear(); $bar.Value = 0
    $reg = Get-CitaviRegistry
    $lblReg.Text = '注册表:Citavi 6 ' + $(if($reg.Installed){'已安装'}else{'未安装'})
    $sp = Get-StartupPaths
    $lblXml.Text = 'StartupSettings6.xml:' + $(if($sp.File){$sp.File}else{'未找到'})
    $script:cit = Resolve-CitaviBin
    $script:wa = Resolve-WordAddInDir
    $txtCit.Text = if ($script:cit) { $script:cit } else { '' }
    $txtWa.Text  = if ($script:wa)  { $script:wa }  else { '' }
    Log "检测完成:"
    Log ("  Citavi 目录     = " + $(if($script:cit){$script:cit}else{'未检测到(请手动选择)'}))
    Log ("  Word 加载项目录 = " + $(if($script:wa){$script:wa}else{'未检测到(可留空跳过)'}))
    Log ("  语言包源        = " + $(if($script:Src){$script:Src}else{'未找到!'}))
    $script:helpSrc = Resolve-HelpSourceDir
    $script:helpDir = Resolve-CustomHelpDir
    Log ("  快速帮助源      = " + $(if($script:helpSrc){$script:helpSrc}else{'未找到(跳过)'}))
    Log ("  快速帮助目标    = " + $script:helpDir)
    $txtHelp.Text = $script:helpDir
    $files = if ($script:Src) { @(Get-ChildItem $script:Src -Filter *.dll).Count } else { 0 }
    Log ("  将复制 {0} 个 DLL;模式:覆盖" -f $files)
}

function Show-Plan($cit,$wa) {
    $t = @()
    if ($cit) { $t += (Join-Path $cit $Culture) }
    if ($wa)  { $t += (Join-Path $wa  $Culture) }
    foreach ($d in $t) { Log ("  · {0}  [{1}]" -f $d, $(if(Test-Path $d){'将覆盖'}else{'新建'})) }
}

function Wait-Processes([string[]]$names) {
    $procs = Get-Running $names
    while ($procs.Count -gt 0) {
        $lines = ($procs | ForEach-Object { "  • $($_.ProcessName)    PID $($_.Id)" }) -join "`r`n"
        $r = [System.Windows.Forms.MessageBox]::Show("需要先关闭以下进程才能继续:`r`n`r`n$lines`r`n`r`n关闭后点「确定」继续;点「取消」放弃。",'请关闭相关进程',[System.Windows.Forms.MessageBoxButtons]::OKCancel,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Cancel) { return $false }
        Start-Sleep -Seconds 1; $procs = Get-Running $names
    }
    return $true
}

function Ensure-Elevated($cit,$wa) {
    if (Test-Admin) { return $true }
    $need = @(); if ($cit -and (Join-Path $cit $Culture) -match 'Program Files') { $need += (Join-Path $cit $Culture) }
    if ($wa  -and (Join-Path $wa  $Culture) -match 'Program Files') { $need += (Join-Path $wa  $Culture) }
    if ($need.Count -eq 0) { return $true }
    $r = [System.Windows.Forms.MessageBox]::Show("写入 Program Files 需要管理员权限。是否以管理员身份重新打开安装器?`r`n`r`n" + ($need -join "`r`n"),'需要提权',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Culture `"$Culture`""
    if ($cit) { $a += " -CitaviBin `"$cit`"" }
    if ($wa)  { $a += " -WordAddInDir `"$wa`"" }
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $a
    return $false
}

function DoInstall([switch]$Uninstall) {
    if (-not $script:Src) { Info '找不到语言包源目录(zh)。' 'Error'; return }
    $cit = $txtCit.Text; $wa = $txtWa.Text
    if (-not (Test-CitaviBin $cit)) { Info 'Citavi 目录无效(缺 Citavi.exe / SwissAcademic.dll)。' 'Error'; return }
    if ($wa -and -not (Test-WordAddInDir $wa)) { Info 'Word 加载项目录无效(缺 SwissAcademic.Citavi.WordAddIn.dll),或清空该框跳过。' 'Error'; return }
    if (-not (Ensure-Elevated $cit $wa)) { Log '已取消(未提权)。'; return }
    $hDir = if ($txtHelp.Text) { $txtHelp.Text } else { $script:helpDir }

    Log ''; Log $(if($Uninstall){'卸载计划:'}else{'安装计划:'})
    Show-Plan $cit $wa
    if (-not $Uninstall) { $files = @(Get-ChildItem $script:Src -Filter *.dll).Count; Log ("  文件数:{0}" -f $files) }
    if ($script:helpSrc) { Log ("  · 快速帮助 -> {0}  ({1} 个 .zh.rtf)" -f $hDir, @(Get-ChildItem $script:helpSrc -Filter *.zh.rtf).Count) }

    $targets = @()
    $targets += [pscustomobject]@{ Kind='Citavi bin'; Dir=(Join-Path $cit $Culture); Procs=@('Citavi') }
    if ($wa) { $targets += [pscustomobject]@{ Kind='Word 加载项'; Dir=(Join-Path $wa $Culture); Procs=@('WINWORD') } }

    $bar.Maximum = $targets.Count; $bar.Value = 0
    foreach ($t in $targets) {
        Log ''
        Log ("→ " + $(if($Uninstall){'卸载 '}else{'安装 '}) + $t.Kind + ':' + $t.Dir)
        if (-not (Wait-Processes $t.Procs)) { Log '已取消。'; return }
        try {
            if ($Uninstall) {
                if (Test-Path $t.Dir) { Remove-Item $t.Dir -Recurse -Force; Log '  已删除。' } else { Log '  跳过(不存在)。' }
            } else {
                if (Test-Path $t.Dir) { Remove-Item $t.Dir -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $t.Dir | Out-Null
                Copy-Item (Join-Path $script:Src '*.dll') $t.Dir -Force
                Log ("  已写入 {0} 个文件。" -f @(Get-ChildItem $t.Dir -Filter *.dll).Count)
            }
        } catch { Log ("  失败:" + $_.Exception.Message); Info $_.Exception.Message 'Error'; return }
        $bar.Value++
    }
    # 快速帮助(Custom Help)
    if ($script:helpSrc -and $hDir) {
        Log ''
        if ($Uninstall) {
            if (Test-Path $hDir) { Remove-Item (Join-Path $hDir '*.zh.rtf') -Force -ErrorAction SilentlyContinue; Log '  已删除快速帮助文件。' }
        } else {
            New-Item -ItemType Directory -Force -Path $hDir | Out-Null
            Copy-Item (Join-Path $script:helpSrc '*.zh.rtf') $hDir -Force
            Log ("  已安装 {0} 个快速帮助文件。" -f @(Get-ChildItem $hDir -Filter *.zh.rtf).Count)
        }
    }
    $msg = if ($Uninstall) { '卸载完成。' } else { "安装完成。`r`n`r`n下一步:打开 Citavi → 工具 → 语言 → 选择「中文」;`r`n快速帮助已写入(重启 Citavi 生效);如装了 Word 加载项,请重启 Word。" }
    Info $msg 'Information'; Log ''; Log $msg
}

$btnBrowseCit.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = '选择 Citavi 的 bin 目录(含 Citavi.exe / SwissAcademic.dll)'
    if ($script:cit) { $fbd.SelectedPath = $script:cit }
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtCit.Text = $fbd.SelectedPath }
})
$btnBrowseWa.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = '选择 Word 加载项目录(含 SwissAcademic.Citavi.WordAddIn.dll)'
    if ($script:wa) { $fbd.SelectedPath = $script:wa }
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtWa.Text = $fbd.SelectedPath }
})
$btnBrowseHelp.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = '选择 Citavi 的 Custom Help 目录(快速帮助)'
    if ($script:helpDir) { $fbd.SelectedPath = $script:helpDir }
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtHelp.Text = $fbd.SelectedPath }
})
$btnDetect.Add_Click({ DoDetect })
$btnInstall.Add_Click({ DoInstall })
$btnUninstall.Add_Click({ DoInstall -Uninstall })
$btnExit.Add_Click({ $form.Close() })

$form.Add_Shown({ DoDetect })
[void]$form.ShowDialog()