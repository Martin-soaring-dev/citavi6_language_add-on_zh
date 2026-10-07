; Citavi 6 中文语言包 —— Inno Setup 安装脚本
; 由 tools/Build-Installer.ps1 调用 ISCC 编译。
; 通过命令行传入: /DRepoRoot=<绝对路径>  /DAppVersion=0.102

#ifndef RepoRoot
  #define RepoRoot "..\.."
#endif
#ifndef AppVersion
  #define AppVersion "0.102"
#endif

[Setup]
AppId={{8E2C6E2A-6C1B-4F1E-9B7A-9E2D5B7C1A01}
AppName=Citavi 6 中文语言包
AppVersion={#AppVersion}
AppVerName=Citavi 6 中文语言包 {#AppVersion}
AppPublisher=Citavi 中文社区汉化项目
AppComments=安装后请在 Citavi「工具 → 语言」中选择「中文」。
DefaultDirName={code:GetDetectedCitaviBin}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
#ifdef TestLowest
PrivilegesRequired=lowest
#else
PrivilegesRequired=admin
#endif
WizardStyle=modern
OutputDir={#RepoRoot}\dist
OutputBaseFilename=Citavi6-zh-Setup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
UninstallDisplayName=Citavi 6 中文语言包 {#AppVersion}
AllowNoIcons=yes
UsePreviousAppDir=yes
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=no

[Files]
; 语言包(7 个附属程序集) → Citavi bin\zh
Source: "{#RepoRoot}\dist\zh\*.dll"; DestDir: "{code:GetCitaviBinDest}\zh"; Flags: ignoreversion
; 语言包 → Word 加载项\zh(可选)
Source: "{#RepoRoot}\dist\zh\*.dll"; DestDir: "{code:GetWordBinDest}\zh"; Flags: ignoreversion; Check: WantWord
; 快速帮助 → Custom Help(可选)
Source: "{#RepoRoot}\custom-help\*.zh.rtf"; DestDir: "{code:GetHelpDest}"; Flags: ignoreversion; Check: WantHelp

[Run]
; 完成后提示(无需运行程序)

[Code]
var
  DirPage: TInputDirWizardPage;
  ChkWord, ChkHelp: TNewCheckBox;
  RefreshBtn: TNewButton;
  OldNextClick: TNotifyEvent;

function BS(const S: String): String;
begin
  if (S <> '') and (S[Length(S)] <> '\') then
    Result := S + '\'
  else
    Result := S;
end;

function Between(const S, A, B: String): String;
var p, q: Integer;
begin
  Result := '';
  p := Pos(A, S);
  if p = 0 then Exit;
  p := p + Length(A);
  q := Pos(B, Copy(S, p, MaxInt));
  if q = 0 then Result := Copy(S, p, MaxInt) else Result := Copy(S, p, q - 1);
end;

function NormDocs(const S: String): String;
var t: String;
begin
  t := S;
  StringChangeEx(t, '%MyDocuments%', ExpandConstant('{userdocs}'), True);
  StringChangeEx(t, '%UserProfile%', ExpandConstant('{%USERPROFILE}'), True);
  StringChangeEx(t, '\\', '\', False);
  Result := t;
end;

// 读取命令行覆盖参数,如 /CITAVIBIN="D:\...\bin"(便于静默部署/测试)
function CmdValue(const Key: String): String;
var tail, up, rest, val: String; p, i: Integer;
begin
  Result := '';
  tail := GetCmdTail;
  if tail = '' then Exit;
  up := UpperCase(tail);
  p := Pos('/' + UpperCase(Key) + '=', up);
  if p = 0 then Exit;
  rest := Trim(Copy(tail, p + Length(Key) + 2, MaxInt));
  if (rest <> '') and (rest[1] = '"') then
  begin
    rest := Copy(rest, 2, MaxInt);
    i := Pos('"', rest);
    if i > 0 then val := Copy(rest, 1, i - 1) else val := rest;
  end
  else
  begin
    i := Pos(' ', rest);
    if i > 0 then val := Copy(rest, 1, i - 1) else val := rest;
  end;
  Result := val;
end;

function IsCitaviBin(const Dir: String): Boolean;
begin
  Result := (Dir <> '') and FileExists(BS(Dir) + 'Citavi.exe');
end;

function IsWordBin(const Dir: String): Boolean;
begin
  Result := (Dir <> '') and FileExists(BS(Dir) + 'SwissAcademic.Citavi.WordAddIn.dll');
end;

function StartupCitaviBin(): String;
var Lines: TArrayOfString; i: Integer; app: String;
begin
  Result := '';
  if LoadStringsFromFile(ExpandConstant('{userappdata}\Swiss Academic Software\StartupSettings6.xml'), Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
    begin
      app := Between(Lines[i], '<ApplicationFolder>', '</ApplicationFolder>');
      if (Result = '') and IsCitaviBin(app) then Result := app;
    end;
end;

function StartupWordBin(): String;
var Lines: TArrayOfString; i: Integer; app: String;
begin
  Result := '';
  if LoadStringsFromFile(ExpandConstant('{userappdata}\Swiss Academic Software\StartupSettings6.xml'), Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
    begin
      app := Between(Lines[i], '<ApplicationFolder>', '</ApplicationFolder>');
      if (Result = '') and IsWordBin(app) then Result := app;
    end;
end;

function DetectCitaviBin(): String;
var p, bin: String;
begin
  Result := '';
  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Swiss Academic Software\Citavi 6', 'Path', p) and IsCitaviBin(ExtractFileDir(p)) then
    Result := ExtractFileDir(p);
  if (Result = '') and RegQueryStringValue(HKLM, 'SOFTWARE\Swiss Academic Software\Citavi 6', 'Path', p) and IsCitaviBin(ExtractFileDir(p)) then
    Result := ExtractFileDir(p);
  if (Result = '') and RegQueryStringValue(HKCU, 'SOFTWARE\Swiss Academic Software\Citavi 6', 'Path', p) and IsCitaviBin(ExtractFileDir(p)) then
    Result := ExtractFileDir(p);
  if (Result = '') and IsCitaviBin(ExpandConstant('{pf32}\Citavi 6\bin')) then Result := ExpandConstant('{pf32}\Citavi 6\bin');
  if (Result = '') and IsCitaviBin(ExpandConstant('{pf}\Citavi 6\bin')) then Result := ExpandConstant('{pf}\Citavi 6\bin');
  if Result = '' then Result := StartupCitaviBin();
  if Result = '' then Result := ExpandConstant('{pf32}\Citavi 6\bin');
end;

function DetectWordBin(): String;
begin
  Result := '';
  if IsWordBin(ExpandConstant('{pf}\Microsoft Office\Root\Office16\ADDINS\Citavi Word AddIn')) then Result := ExpandConstant('{pf}\Microsoft Office\Root\Office16\ADDINS\Citavi Word AddIn');
  if (Result = '') and IsWordBin(ExpandConstant('{pf}\Microsoft Office\Root\Office15\ADDINS\Citavi Word AddIn')) then Result := ExpandConstant('{pf}\Microsoft Office\Root\Office15\ADDINS\Citavi Word AddIn');
  if (Result = '') and IsWordBin(ExpandConstant('{pf}\Microsoft Office\Root\Office14\ADDINS\Citavi Word AddIn')) then Result := ExpandConstant('{pf}\Microsoft Office\Root\Office14\ADDINS\Citavi Word AddIn');
  if Result = '' then Result := StartupWordBin();
end;

function DetectHelpDir(): String;
var Lines: TArrayOfString; i: Integer; udf: String;
begin
  Result := '';
  if LoadStringsFromFile(ExpandConstant('{userappdata}\Swiss Academic Software\StartupSettings6.xml'), Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
    begin
      udf := Between(Lines[i], '<UserDataFolder>', '</UserDataFolder>');
      if (Result = '') and (udf <> '') then Result := BS(NormDocs(udf)) + 'Custom Help';
    end;
  if Result = '' then Result := ExpandConstant('{userdocs}\Citavi 6\Custom Help');
end;

function GetDetectedCitaviBin(Param: String): String;
begin
  Result := DetectCitaviBin();
end;

function GetCitaviBinDest(Param: String): String;
begin
  Result := DirPage.Values[0];
end;

function GetWordBinDest(Param: String): String;
begin
  Result := DirPage.Values[1];
end;

function GetHelpDest(Param: String): String;
begin
  Result := DirPage.Values[2];
end;

function WantWord(): Boolean;
begin
  Result := ChkWord.Checked and (DirPage.Values[1] <> '');
end;

function WantHelp(): Boolean;
begin
  Result := ChkHelp.Checked and (DirPage.Values[2] <> '');
end;

procedure RefreshPaths(Sender: TObject);
begin
  DirPage.Values[0] := DetectCitaviBin();
  DirPage.Values[1] := DetectWordBin();
  DirPage.Values[2] := DetectHelpDir();
  ChkWord.Checked := (DirPage.Values[1] <> '');
  ChkHelp.Checked := (DirPage.Values[2] <> '');
end;

// 取消勾选时清空框(=跳过);重新勾选时补上自动探测值
procedure WordCheckClick(Sender: TObject);
begin
  if ChkWord.Checked then
  begin
    if DirPage.Values[1] = '' then DirPage.Values[1] := DetectWordBin();
    if DirPage.Values[1] = '' then DirPage.Values[1] := DetectCitaviBin();
  end
  else
    DirPage.Values[1] := '';
end;

procedure HelpCheckClick(Sender: TObject);
begin
  if ChkHelp.Checked then
  begin
    if DirPage.Values[2] = '' then DirPage.Values[2] := DetectHelpDir();
  end
  else
    DirPage.Values[2] := '';
end;

// 重写 Next:允许把可选目录留空(=跳过)。
// Inno 的 TInputDirWizardPage 硬性要求每个框都是合法路径;这里在校验前给空框
// 临时填一个合法值,通过校验后再还原为空。
procedure NextClick(Sender: TObject);
var empty1, empty2: Boolean;
begin
  if WizardForm.CurPageID = DirPage.ID then
  begin
    if not IsCitaviBin(DirPage.Values[0]) then
    begin
      MsgBox('Citavi 目录无效:未找到 Citavi.exe,请选择 Citavi 6 的 bin 目录。', mbError, MB_OK);
      Exit;
    end;
    if ChkWord.Checked and not IsWordBin(DirPage.Values[1]) then
    begin
      MsgBox('Word 加载项目录无效:未找到 SwissAcademic.Citavi.WordAddIn.dll。' + #13#10 +
             '请修正,或取消勾选「安装到 Word 加载项」以跳过。', mbError, MB_OK);
      Exit;
    end;
  end;

  empty1 := (DirPage.Values[1] = '');
  empty2 := (DirPage.Values[2] = '');
  if empty1 then DirPage.Values[1] := ExpandConstant('{win}');
  if empty2 then DirPage.Values[2] := ExpandConstant('{win}');

  OldNextClick(Sender);

  if empty1 then DirPage.Values[1] := '';
  if empty2 then DirPage.Values[2] := '';
end;

procedure InitializeWizard();
var v: String;
begin
  DirPage := CreateInputDirPage(wpSelectComponents, '选择安装位置',
    '安装器已自动检测下列目录,可手动修改;留空或取消勾选 = 跳过该项。',
    '', False, '');
  DirPage.Add('Citavi 6 的 bin 目录(必填):');
  DirPage.Add('Word 加载项目录:');
  DirPage.Add('「快速帮助」目录:');
  DirPage.Values[0] := DetectCitaviBin();
  DirPage.Values[1] := DetectWordBin();
  DirPage.Values[2] := DetectHelpDir();

  v := CmdValue('CITAVIBIN'); if v <> '' then DirPage.Values[0] := v;
  v := CmdValue('WORDBIN');   if v <> '' then DirPage.Values[1] := v;
  v := CmdValue('HELPDIR');   if v <> '' then DirPage.Values[2] := v;

  // “重新检测”按钮:一键重新自动探测三个路径
  RefreshBtn := TNewButton.Create(WizardForm);
  RefreshBtn.Parent := DirPage.Surface;
  RefreshBtn.Width := ScaleX(120);
  RefreshBtn.Height := ScaleY(25);
  RefreshBtn.Left := DirPage.Edits[2].Left;
  RefreshBtn.Top := DirPage.Edits[2].Top + DirPage.Edits[2].Height + ScaleY(12);
  RefreshBtn.Caption := '重新检测路径';
  RefreshBtn.OnClick := @RefreshPaths;

  // 跳过复选框(运行期创建的复选框需手动缩放高度)
  ChkWord := TNewCheckBox.Create(WizardForm);
  ChkWord.Parent := DirPage.Surface;
  ChkWord.Left := DirPage.Edits[0].Left;
  ChkWord.Top := RefreshBtn.Top + RefreshBtn.Height + ScaleY(12);
  ChkWord.Width := ScaleX(220);
  ChkWord.Height := ScaleY(17);
  ChkWord.Caption := '安装到 Word 加载项';
  ChkWord.OnClick := @WordCheckClick;

  ChkHelp := TNewCheckBox.Create(WizardForm);
  ChkHelp.Parent := DirPage.Surface;
  ChkHelp.Left := ChkWord.Left + ScaleX(230);
  ChkHelp.Top := ChkWord.Top;
  ChkHelp.Width := ScaleX(220);
  ChkHelp.Height := ScaleY(17);
  ChkHelp.Caption := '安装「快速帮助」中文';
  ChkHelp.OnClick := @HelpCheckClick;

  ChkWord.Checked := (DirPage.Values[1] <> '');
  ChkHelp.Checked := (DirPage.Values[2] <> '');

  // 覆盖 Next 点击,使“留空=跳过”生效
  OldNextClick := WizardForm.NextButton.OnClick;
  WizardForm.NextButton.OnClick := @NextClick;
end;