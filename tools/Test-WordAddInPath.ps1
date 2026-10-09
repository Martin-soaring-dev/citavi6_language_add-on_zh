#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Word 加载项路径探测契约回归验证。

.DESCRIPTION
    覆盖规格 word-addin-path-detection 的验收矩阵:
      A) 64 位 Office 真实目录可判定
      B) Citavi bin 不可判定为 Word 加载项
      C) 自动解析命中真实加载项目录
      D) 显式指定无效路径报错
      E) 空态返回 null(不回退 Citavi bin)
    退出码:0 全部通过;1 有失败。
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoDir 'tools\lib\Resolve-WordAddInPath.ps1')

$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green }
    else { Write-Host "FAIL  $name  $detail" -ForegroundColor Red; $script:fail++ }
}

# A) 真实 Word 加载项(本机 64 位 Office)
$realWa = 'C:\Program Files\Microsoft Office\Root\Office16\ADDINS\Citavi Word AddIn'
if (-not (Test-IsValidWordAddInDir $realWa)) {
    $realWa = Resolve-WordAddInDir
}
Check 'A1 真实加载项目录判定通过' ([bool]$realWa -and (Test-IsValidWordAddInDir $realWa)) "realWa=$realWa"

# B) Citavi bin 不得通过
$citCandidates = @(
    'D:\Program Files (x86)\Citavi 6\bin',
    'C:\Program Files (x86)\Citavi 6\bin',
    'C:\Program Files\Citavi 6\bin'
) | Where-Object { Test-Path (Join-Path $_ 'Citavi.exe') } | Select-Object -First 1
if ($citCandidates) {
    Check 'B1 Citavi bin 被排除' (-not (Test-IsValidWordAddInDir $citCandidates)) "cit=$citCandidates"
} else {
    Write-Host 'SKIP  B1 本机未找到 Citavi bin' -ForegroundColor Yellow
}

# C) 自动解析
$auto = Resolve-WordAddInDir
Check 'C1 自动解析得到有效目录' ([bool]$auto -and (Test-IsValidWordAddInDir $auto)) "auto=$auto"
Check 'C2 自动解析结果不是 Citavi bin' ([bool]$auto -and -not (Test-Path (Join-Path $auto 'Citavi.exe'))) "auto=$auto"

# D) 显式无效覆盖
$threw = $false
try { $null = Resolve-WordAddInDir -Override 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs' -ThrowOnInvalidOverride }
catch { $threw = $true }
Check 'D1 无效 Override 抛错' $threw

# D2) 显式有效覆盖原样返回
if ($realWa) {
    $ov = Resolve-WordAddInDir -Override $realWa -ThrowOnInvalidOverride
    $ovOk = $ov -and ((Resolve-Path -LiteralPath $ov).Path -eq (Resolve-Path -LiteralPath $realWa).Path)
    Check 'D2 有效 Override 原样返回' $ovOk "ov=$ov realWa=$realWa"
} else {
    Write-Host 'SKIP  D2 无真实加载项目录' -ForegroundColor Yellow
}

# E) 空 Override = 自动,不应返回 Citavi bin
$empty = Resolve-WordAddInDir -Override ''
Check 'E1 空 Override 走自动探测' ([bool]$empty -and (Test-IsValidWordAddInDir $empty)) "empty=$empty"

Write-Host ''
Write-Host ("结果: {0} 失败" -f $fail)
if ($fail -gt 0) { exit 1 }
exit 0
