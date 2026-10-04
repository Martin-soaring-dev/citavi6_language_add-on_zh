' 启动 Citavi 中文语言包安装器(GUI,无控制台窗口)
Option Explicit
Dim fso, sh, d, ps
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
d = fso.GetParentFolderName(WScript.ScriptFullName)
ps = d & "\Install-Gui.ps1"
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps & """", 0, False