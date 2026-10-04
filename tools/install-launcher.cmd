@echo off
chcp 65001 >nul
title Citavi 6 Chinese Language Pack Installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Toolkit.ps1" %*
echo.
pause