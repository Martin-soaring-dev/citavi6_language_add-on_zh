' Launch the Citavi Chinese language-pack installer (GUI).
' Requests admin rights at startup (UAC). Passes the current user's paths
' to the elevated process so Documents/AppData stay correct even when UAC
' elevates under a different admin account.
Option Explicit
Dim fso, sh, d, ps, up, ad, docs, args, rc
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
d    = fso.GetParentFolderName(WScript.ScriptFullName)
ps   = fso.BuildPath(d, "Install-Gui.ps1")
up   = sh.ExpandEnvironmentStrings("%USERPROFILE%")
ad   = sh.ExpandEnvironmentStrings("%APPDATA%")
docs = sh.SpecialFolders("MyDocuments")

args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps & """ -Elevated" _
     & " -UserProfile """ & up & """" _
     & " -UserAppData """ & ad & """" _
     & " -UserDocuments """ & docs & """"

' Elevated launch (triggers UAC).
On Error Resume Next
CreateObject("Shell.Application").ShellExecute "powershell.exe", args, d, "runas", 1
rc = Err.Number
On Error GoTo 0

If rc <> 0 Then
  ' UAC declined or elevation unavailable: fall back to a normal launch
  ' (the GUI will ask for elevation again only when writing to Program Files).
  sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps & """", 0, False
End If