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
    [string]$UserProfile = '',
    [string]$UserAppData = '',
    [string]$UserDocuments = '',
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ================= 共用函数(与 CLI 版一致) =================
function Test-Admin { try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false } }
function Get-StartupSettingsFile {
    # 提权后可能运行在别的账户下,优先使用启动器传入的“当前用户”路径
    $appData = if ($UserAppData) { $UserAppData } else { $env:APPDATA }
    $profile = if ($UserProfile) { $UserProfile } else { $env:USERPROFILE }
    $known = Join-Path $appData 'Swiss Academic Software\StartupSettings6.xml'
    if (Test-Path $known) { return $known }
    foreach ($r in @($appData, (Join-Path $profile 'AppData\Local'), "$env:ProgramData", (Join-Path $profile 'Documents'))) {
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
# Word 加载项:与 Setup.exe 共用契约(tools/lib/Resolve-WordAddInPath.ps1)
. (Join-Path $PSScriptRoot 'lib/Resolve-WordAddInPath.ps1')
function Test-WordAddInDir([string]$p){ return Test-IsValidWordAddInDir $p }
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
    $docs = if ($UserDocuments) { $UserDocuments } else { [Environment]::GetFolderPath('MyDocuments') }
    $profile = if ($UserProfile) { $UserProfile } else { $env:USERPROFILE }
    if ($ud) {
        $ud = $ud -replace '%MyDocuments%', $docs
        $ud = $ud -replace '%UserProfile%', $profile
        $ud = [Environment]::ExpandEnvironmentVariables($ud)
        $ud = $ud -replace '\\\\','\'
        return (Join-Path $ud 'Custom Help')
    }
    return (Join-Path $docs 'Citavi 6\Custom Help')
}
function Get-Running([string[]]$names){ return @(Get-Process -Name $names -ErrorAction SilentlyContinue) }

# ================= 状态 =================
$script:Src = Resolve-SourceDir
$script:InstallProc = @{ 'Citavi bin' = @('Citavi'); 'Word 加载项' = @('WINWORD') }

# ================= 窗体 =================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Citavi 6 中文语言包 安装器  v0.103'
$form.Size = New-Object System.Drawing.Size(660, 634)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(660, 550)

# 品牌视觉:资产在 ZIP 里是 assets\,在源码仓库里是 docs\brand\simple\export\win\;都找不到则不带图。
function Resolve-AssetDir {
    $cands = @(
        (Join-Path $PSScriptRoot 'assets'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\brand\simple\export\win')
    )
    foreach ($d in $cands) { if ($d -and (Test-Path (Join-Path $d 'setup.ico'))) { return $d } }
    return ''
}
$assetDir = Resolve-AssetDir
if ($assetDir) {
    try { $form.Icon = New-Object System.Drawing.Icon((Join-Path $assetDir 'setup.ico')) } catch { }
    $logoFile = Join-Path $assetDir 'logo-symbol.png'
    if (Test-Path $logoFile) {
        $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($logoFile))
        $tmp = [System.Drawing.Image]::FromStream($ms)
        try {
            $picLogo = New-Object System.Windows.Forms.PictureBox
            $picLogo.SizeMode = 'Zoom'
            $picLogo.Location = New-Object System.Drawing.Point(566, 6)
            $picLogo.Size = New-Object System.Drawing.Size(70, 45)
            # 复制成独立 Bitmap,避免 GDI+ 锁住 PNG 文件(解压目录可能被用户直接删掉)。
            $picLogo.Image = New-Object System.Drawing.Bitmap($tmp)
            $form.Controls.Add($picLogo)
        } finally { $tmp.Dispose(); $ms.Dispose() }
    }
}

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Citavi 6 中文语言包(社区汉化)'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(14, 10); $lblTitle.Size = New-Object System.Drawing.Size(470, 28)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '自动检测安装路径(注册表判定安装 → StartupSettings6.xml 取路径);可手动修改。'
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$lblSub.Location = New-Object System.Drawing.Point(16, 40); $lblSub.Size = New-Object System.Drawing.Size(544, 18)
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

# 许可同意门:未同意不得安装(卸载不需要同意 —— 移除随时允许)
$chkAgree = New-Object System.Windows.Forms.CheckBox
$chkAgree.Text = '同意使用条款'; $chkAgree.Location = New-Object System.Drawing.Point(116, 522); $chkAgree.Size = New-Object System.Drawing.Size(150, 18)
$chkAgree.Checked = $false
$form.Controls.Add($chkAgree)
$btnLicense = New-Object System.Windows.Forms.Button
$btnLicense.Text = '查看条款…'; $btnLicense.Location = New-Object System.Drawing.Point(272, 516); $btnLicense.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnLicense)

# 底部署名(与 Setup 向导 [Code] 里的自建标签同一口径、同样两行)
$lblAuthor = New-Object System.Windows.Forms.Label
$lblAuthor.Text = "Citavi 6 中文语言包 · 社区汉化`r`n@Martin-soaring-dev · CC BY-NC 4.0"
$lblAuthor.ForeColor = [System.Drawing.Color]::Gray
$lblAuthor.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$lblAuthor.Location = New-Object System.Drawing.Point(12, 552); $lblAuthor.Size = New-Object System.Drawing.Size(620, 34)
$form.Controls.Add($lblAuthor)

function Log([string]$m){ $txtLog.AppendText($m + "`r`n"); $txtLog.SelectionStart = $txtLog.TextLength; $txtLog.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() }
function Info($t,$c='Information'){ return [System.Windows.Forms.MessageBox]::Show($t,'Citavi 中文语言包',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::$c) }

function Get-LicenseText {
    foreach ($c in @((Join-Path $PSScriptRoot '使用条款.txt'), (Join-Path $PSScriptRoot 'installer\license.zh.txt'))) {
        if (Test-Path $c) { return [IO.File]::ReadAllText($c, [Text.Encoding]::UTF8) }
    }
    return ''
}

# 许可条款模态框:返回 $true 表示用户明确接受
function Show-License {
    $body = Get-LicenseText
    if (-not $body) {
        # 只单独拷了脚本、条款文件没跟过来时,至少把署名、许可与官方渠道讲清楚。
        $body = "本项目由「Citavi 中文社区汉化项目」维护(作者 GitHub:@Martin-soaring-dev),`r`n以 CC BY-NC 4.0 发布,禁止任何商业性使用。`r`n`r`n唯一官方分发渠道:`r`nhttps://github.com/Martin-soaring-dev/citavi6_language_add-on_zh/releases`r`n`r`n(未能读取包内「使用条款.txt」,以上为条款要点。)"
    }
    $lf = New-Object System.Windows.Forms.Form
    $lf.Text = '使用条款与许可声明'; $lf.Size = New-Object System.Drawing.Size(640, 520)
    $lf.StartPosition = 'CenterParent'; $lf.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $lf.MinimizeBox = $false; $lf.ShowInTaskbar = $false
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = 'Vertical'
    $txt.Dock = 'Fill'; $txt.BorderStyle = 'None'; $txt.Text = $body
    $lf.Controls.Add($txt)
    $pnl = New-Object System.Windows.Forms.Panel; $pnl.Dock = 'Bottom'; $pnl.Height = 44
    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = '不同意'; $btnNo.DialogResult = 'Cancel'
    $btnNo.Location = New-Object System.Drawing.Point(330, 8); $btnNo.Size = New-Object System.Drawing.Size(90, 28)
    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = '我接受,继续安装'; $btnYes.DialogResult = 'OK'
    $btnYes.Location = New-Object System.Drawing.Point(430, 8); $btnYes.Size = New-Object System.Drawing.Size(140, 28)
    $pnl.Controls.Add($btnNo); $pnl.Controls.Add($btnYes)
    $lf.Controls.Add($pnl)
    $lf.AcceptButton = $btnYes; $lf.CancelButton = $btnNo
    try { $ok = ($lf.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) } finally { $lf.Dispose() }
    return $ok
}

function DoDetect {
    $txtLog.Clear(); $bar.Value = 0
    $reg = Get-CitaviRegistry
    $lblReg.Text = '注册表:Citavi 6 ' + $(if($reg.Installed){'已安装'}else{'未安装'})
    $sp = Get-StartupPaths
    $lblXml.Text = 'StartupSettings6.xml:' + $(if($sp.File){$sp.File}else{'未找到'})
    $script:cit = Resolve-CitaviBin
    # 显式 -WordAddInDir 无效必须失败，禁止静默改成空路径
    $script:wa = Resolve-WordAddInDir -Override $WordAddInDir -ThrowOnInvalidOverride
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
    $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Culture `"$Culture`" -Elevated"
    if ($cit) { $a += " -CitaviBin `"$cit`"" }
    if ($wa)  { $a += " -WordAddInDir `"$wa`"" }
    if ($script:helpDir) { $a += " -CustomHelpDir `"$script:helpDir`"" }
    $a += " -UserProfile `"$env:USERPROFILE`" -UserAppData `"$env:APPDATA`" -UserDocuments `"$([Environment]::GetFolderPath('MyDocuments'))`""
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $a
    return $false
}

function DoInstall([switch]$Uninstall) {
    if (-not $script:Src) { Info '找不到语言包源目录(zh)。' 'Error'; return }
    $cit = $txtCit.Text; $wa = $txtWa.Text
    if (-not (Test-CitaviBin $cit)) { Info 'Citavi 目录无效(缺 Citavi.exe / SwissAcademic.dll)。' 'Error'; return }
    if ($wa -and -not (Test-WordAddInDir $wa)) { Info 'Word 加载项目录无效:需含 SwissAcademic.Citavi.WordAddIn.dll 且不能是 Citavi bin,或清空该框跳过。' 'Error'; return }
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
$btnInstall.Add_Click({
    if (-not $chkAgree.Checked) {
        if (Show-License) { $chkAgree.Checked = $true } else { Log '已取消:未同意使用条款,不执行安装。'; return }
    }
    DoInstall
})
$btnLicense.Add_Click({ if (Show-License) { $chkAgree.Checked = $true } })
$btnUninstall.Add_Click({ DoInstall -Uninstall })
$btnExit.Add_Click({ $form.Close() })

$form.Add_Shown({ DoDetect })
[void]$form.ShowDialog()