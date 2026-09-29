#!/usr/bin/env pwsh
<#
.SYNOPSIS
    安装并启动 translate-mcp-server(用于翻译 translations/*.tsv 的 MCP 翻译服务)。

.DESCRIPTION
    1. 克隆 https://github.com/baggiogan2000/translate-mcp-server
    2. 安装 Python 依赖(requests / urllib3)
    3. 打补丁:移除 GoogleTranslator.query() 中会静默删除 `?` `’` `–` 等字符的白名单过滤
       原始代码:
           q = re.sub(r'''[^...]''', '', q)
       替换为(仅去除控制字符):
           q = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', q)
    4. 可选启动 SSE 服务(默认端口 38089)

.PARAMETER Dir
    安装目录,默认 %LOCALAPPDATA%\Temp\translate-mcp。

.PARAMETER Port
    服务端口,默认 38089。

.PARAMETER Start
    安装后启动服务(前台运行)。

.EXAMPLE
    pwsh ./tools/Setup-TranslateMcp.ps1 -Start
#>
[CmdletBinding()]
param(
    [string]$Dir = (Join-Path $env:LOCALAPPDATA 'translate-mcp'),

    [int]$Port = 38089,

    [switch]$Start
)

$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/baggiogan2000/translate-mcp-server.git'

if (-not (Test-Path (Join-Path $Dir 'sse_server.py'))) {
    Write-Host "克隆 $repo ..."
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    git clone --depth 1 $repo $Dir
} else {
    Write-Host "已存在:$Dir"
}

Write-Host '安装 Python 依赖 ...'
python -m pip install -q requests urllib3

# 打补丁:替换破坏性白名单过滤
$g = Join-Path $Dir 'GoogleTranslator.py'
$src = [System.IO.File]::ReadAllText($g)
$pattern = "(?m)^\s*q = re\.sub\(r'''(?s).*?''', '', q\)\s*$"
if ($src -match $pattern) {
    $safe = "        q = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', q)  # patched: 仅去控制字符"
    $src = [regex]::Replace($src, $pattern, $safe)
    [System.IO.File]::WriteAllText($g, $src, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '已打补丁:移除破坏性字符白名单过滤。' -ForegroundColor Green
} else {
    Write-Warning '未找到需要替换的过滤行(可能已被修补或上游已修改)。'
}

if ($Start) {
    # 关键:服务器会 print 日志,中文 Windows 下默认 GBK 编码会让 print 抛
    # UnicodeEncodeError -> POST 返回 400 / SSE 连接中断。强制 UTF-8。
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    Write-Host "启动 MCP 服务: http://localhost:$Port/sse"
    Push-Location $Dir
    try { python sse_server.py } finally { Pop-Location }
}
