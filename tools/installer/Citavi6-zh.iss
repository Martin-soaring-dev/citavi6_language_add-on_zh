; Citavi 6 中文语言包 —— Inno Setup 安装脚本
; 由 tools/Build-Installer.ps1 调用 ISCC 编译。
; 通过命令行传入: /DRepoRoot=<绝对路径>  /DAppVersion=0.103
; 品牌位图资产由 tools/Build-BrandAssets.ps1 从 docs/brand/simple/svg 生成并提交入库。

#ifndef RepoRoot
  #define RepoRoot "..\.."
#endif
#ifndef AppVersion
  #define AppVersion "0.103"
#endif

#define RepoURL "https://github.com/Martin-soaring-dev/citavi6_language_add-on_zh"

[Setup]
AppId={{8E2C6E2A-6C1B-4F1E-9B7A-9E2D5B7C1A01}
AppName=Citavi 6 中文语言包
AppVersion={#AppVersion}
AppVerName=Citavi 6 中文语言包 {#AppVersion}
AppPublisher=Citavi 中文社区汉化项目
AppPublisherURL={#RepoURL}
AppSupportURL={#RepoURL}/issues
AppUpdatesURL={#RepoURL}/releases/latest
AppComments=安装后请在 Citavi「工具 → 语言」中选择「中文」。

; 许可页(.txt 必须是 UTF-8 或 UTF-16LE;换行符由 .gitattributes 钉成 CRLF)
LicenseFile=license.zh.txt
InfoAfterFile=infoafter.zh.txt

; 作者与版权写进 Setup.exe 的文件属性 —— 再分发时最难抹掉的一处举证。
; 注意:实测 Inno 把每条 VersionInfo 值截到 100 个字符,超了会静默丢尾巴,所以这里刻意压短。
VersionInfoCompany=Citavi 中文社区汉化项目 (@Martin-soaring-dev)
VersionInfoCopyright=© 2026 Citavi 中文社区汉化项目 · CC BY-NC 4.0 · github.com/Martin-soaring-dev/citavi6_language_add-on_zh
VersionInfoDescription=Citavi 6 简体中文语言包 安装程序(社区汉化,非官方)
VersionInfoProductName=Citavi 6 中文语言包
VersionInfoVersion={#AppVersion}
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

; 尺寸是硬约束:wizard-image 必须保持 164:314(Inno 按此比例缩放,656x1256 覆盖到 250% DPI)、
; wizard-small 必须是正方形、setup.ico 必须含 16/32/48/64/256 帧。改图请重跑 tools/Build-BrandAssets.ps1。
SetupIconFile={#RepoRoot}\docs\brand\simple\export\win\setup.ico
WizardImageFile={#RepoRoot}\docs\brand\simple\export\win\wizard-image.png
WizardSmallImageFile={#RepoRoot}\docs\brand\simple\export\win\wizard-small.png
; 卸载项图标取卸载程序(已内嵌 SetupIconFile),这样不必往 Citavi 目录里多放一个 .ico。
UninstallDisplayIcon={uninstallexe}

[Messages]
; 署名不放这里:BeveledLabel 按单行设计并垂直居中在底部条带内,给它两行会同时压到上方的
; 「我接受协议」单选框和下方的 Next/Cancel(实测)。署名改由 [Code] 里的底对齐标签绘制。
; 同意与否这个动作不能靠猜英文,单独把许可页这三条覆盖成中文(向导其余文案仍为英文)
LicenseLabel3=请阅读以下使用条款与许可声明。必须选择「我接受」才能继续安装。
LicenseAccepted=我接受协议(&A)
LicenseNotAccepted=我不接受协议(&D)

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
  AttributionLbl: TNewStaticText;
  OldNextClick: TNotifyEvent;
  CmdCitavi, CmdWord, CmdHelp: String;

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

// Word 加载项目录:有加载项 DLL,且不是 Citavi 自身 bin(bin 里也带同名 DLL)
function IsWordBin(const Dir: String): Boolean;
begin
  Result := (Dir <> '') and (not IsCitaviBin(Dir)) and
    FileExists(BS(Dir) + 'SwissAcademic.Citavi.WordAddIn.dll');
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

// 在 Office 根下拼 ADDINS\Citavi Word AddIn(Root\OfficeXX 与 OfficeXX 两种布局)
function TryOfficeBase(const OfficeRoot: String): String;
var c: String;
begin
  Result := '';
  if OfficeRoot = '' then Exit;

  c := BS(OfficeRoot) + 'Root\Office16\ADDINS\Citavi Word AddIn';
  if IsWordBin(c) then begin Result := c; Exit; end;
  c := BS(OfficeRoot) + 'Office16\ADDINS\Citavi Word AddIn';
  if IsWordBin(c) then begin Result := c; Exit; end;
  c := BS(OfficeRoot) + 'Root\Office15\ADDINS\Citavi Word AddIn';
  if IsWordBin(c) then begin Result := c; Exit; end;
  c := BS(OfficeRoot) + 'Office15\ADDINS\Citavi Word AddIn';
  if IsWordBin(c) then begin Result := c; Exit; end;
  c := BS(OfficeRoot) + 'Root\Office14\ADDINS\Citavi Word AddIn';
  if IsWordBin(c) then begin Result := c; Exit; end;
  c := BS(OfficeRoot) + 'Office14\ADDINS\Citavi Word AddIn';
  if IsWordBin(c) then begin Result := c; Exit; end;
end;

// 注册表:Word InstallRoot / ClickToRun → Office 根(含 64 位视图)
function RegWordBin(): String;
var roots: TArrayOfString; i: Integer; p: String;
begin
  Result := '';
  SetLength(roots, 4);
  roots[0] := 'SOFTWARE\Microsoft\Office\16.0\Word\InstallRoot';
  roots[1] := 'SOFTWARE\Microsoft\Office\15.0\Word\InstallRoot';
  roots[2] := 'SOFTWARE\Microsoft\Office\14.0\Word\InstallRoot';
  roots[3] := '';

  for i := 0 to GetArrayLength(roots) - 1 do
  begin
    p := '';
    if roots[i] <> '' then
    begin
      if RegQueryStringValue(HKLM64, roots[i], 'Path', p) and (p <> '') then
      begin
        // Path 形如 ...\Microsoft Office\root\Office16\ → 其 ADDINS 与上级 Office 根
        Result := TryOfficeBase(ExtractFileDir(RemoveBackslash(p)));
        if Result = '' then Result := TryOfficeBase(ExtractFileDir(ExtractFileDir(RemoveBackslash(p))));
        if Result = '' then Result := TryOfficeBase(ExtractFileDir(ExtractFileDir(ExtractFileDir(RemoveBackslash(p)))));
        if Result <> '' then Exit;
      end;
      if RegQueryStringValue(HKLM, roots[i], 'Path', p) and (p <> '') then
      begin
        Result := TryOfficeBase(ExtractFileDir(RemoveBackslash(p)));
        if Result = '' then Result := TryOfficeBase(ExtractFileDir(ExtractFileDir(RemoveBackslash(p))));
        if Result <> '' then Exit;
      end;
    end;
  end;

  // ClickToRun
  p := '';
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\Office\ClickToRun', 'PackageFolder', p) and (p <> '') then
  begin
    Result := TryOfficeBase(p);
    if Result <> '' then Exit;
  end;
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\Office\ClickToRun', 'InstallPath', p) and (p <> '') then
  begin
    Result := TryOfficeBase(p);
    if Result = '' then Result := TryOfficeBase(ExtractFileDir(RemoveBackslash(p)));
    if Result <> '' then Exit;
  end;
end;

function SearchWordDll(const Root: String; Depth: Integer): String;
var FindRec: TFindRec; sub: String;
begin
  Result := '';
  if (Root = '') or (Depth < 0) then Exit;
  if FindFirst(BS(Root) + '*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          begin
            sub := BS(Root) + FindRec.Name;
            if IsWordBin(sub) then
            begin
              Result := sub;
              Exit;
            end;
            if Depth > 0 then
            begin
              Result := SearchWordDll(sub, Depth - 1);
              if Result <> '' then Exit;
            end;
          end;
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

function FsWordBin(): String;
var p: String;
begin
  Result := '';
  p := ExpandConstant('{pf64}');
  if p <> '' then
  begin
    Result := SearchWordDll(BS(p) + 'Microsoft Office', 5);
    if Result <> '' then Exit;
    Result := SearchWordDll(BS(p) + 'Microsoft Office\root', 5);
    if Result <> '' then Exit;
  end;
  p := ExpandConstant('{pf32}');
  if p <> '' then
  begin
    Result := SearchWordDll(BS(p) + 'Microsoft Office', 5);
    if Result <> '' then Exit;
    Result := SearchWordDll(BS(p) + 'Microsoft Office\root', 5);
    if Result <> '' then Exit;
  end;
  Result := SearchWordDll(ExpandConstant('{localappdata}\Microsoft\Office'), 5);
end;

function DetectCitaviBin(): String;
var p: String;
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

// 探测顺序:注册表推导 → 约定路径(双 Program Files)→ StartupSettings → 文件系统
function DetectWordBin(): String;
var c: String;
begin
  Result := '';
  // 2) 注册表
  Result := RegWordBin();
  if Result <> '' then Exit;
  // 3) 约定路径
  c := TryOfficeBase(ExpandConstant('{pf64}\Microsoft Office'));
  if c <> '' then begin Result := c; Exit; end;
  c := TryOfficeBase(ExpandConstant('{pf32}\Microsoft Office'));
  if c <> '' then begin Result := c; Exit; end;
  c := TryOfficeBase(ExpandConstant('{pf}\Microsoft Office'));
  if c <> '' then begin Result := c; Exit; end;
  // 4) StartupSettings
  Result := StartupWordBin();
  if Result <> '' then Exit;
  // 5) 文件系统
  Result := FsWordBin();
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

// 显式命令行覆盖优先;「重新检测」不得改写用户/命令行已指定的有效路径
procedure RefreshPaths(Sender: TObject);
begin
  if CmdCitavi = '' then DirPage.Values[0] := DetectCitaviBin();
  if CmdWord = '' then DirPage.Values[1] := DetectWordBin();
  if CmdHelp = '' then DirPage.Values[2] := DetectHelpDir();
  ChkWord.Checked := (DirPage.Values[1] <> '');
  ChkHelp.Checked := (DirPage.Values[2] <> '');
end;

// 取消勾选时清空框(=跳过);重新勾选时只用探测结果,禁止回退到 Citavi bin
procedure WordCheckClick(Sender: TObject);
begin
  if ChkWord.Checked then
  begin
    if DirPage.Values[1] = '' then
      DirPage.Values[1] := DetectWordBin();
    if DirPage.Values[1] = '' then
      MsgBox('未自动检测到 Word 加载项目录。' + #13#10 +
             '可手动 Browse 选择(需含 SwissAcademic.Citavi.WordAddIn.dll),' + #13#10 +
             '或取消勾选「安装到 Word 加载项」以跳过。', mbInformation, MB_OK);
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
    if ChkWord.Checked then
    begin
      if DirPage.Values[1] = '' then
      begin
        MsgBox('已勾选「安装到 Word 加载项」,但目录为空。' + #13#10 +
               '请 Browse 选择加载项目录,或取消勾选以跳过。', mbError, MB_OK);
        Exit;
      end;
      if not IsWordBin(DirPage.Values[1]) then
      begin
        MsgBox('Word 加载项目录无效:未找到 SwissAcademic.Citavi.WordAddIn.dll,' + #13#10 +
               '或该目录是 Citavi 6 的 bin(不能作为 Word 加载项目录)。' + #13#10 +
               '请修正,或取消勾选「安装到 Word 加载项」以跳过。', mbError, MB_OK);
        Exit;
      end;
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

  CmdCitavi := CmdValue('CITAVIBIN');
  CmdWord   := CmdValue('WORDBIN');
  CmdHelp   := CmdValue('HELPDIR');
  if CmdCitavi <> '' then DirPage.Values[0] := CmdCitavi;
  if CmdWord   <> '' then DirPage.Values[1] := CmdWord;
  if CmdHelp   <> '' then DirPage.Values[2] := CmdHelp;

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

  // 署名:两行、底对齐到 Next 按钮那一行、靠左。
  // 不用 BeveledLabel —— 它按单行垂直居中在底部条带里,给两行会同时压到上方单选框与下方按钮。
  // AutoSize 必须为 True:控件要贴着文字收缩,否则会给一个空白的宽块,看着像盖住了底部按钮带。
  AttributionLbl := TNewStaticText.Create(WizardForm);
  AttributionLbl.Parent := WizardForm;
  AttributionLbl.AutoSize := True;
  AttributionLbl.Font.Size := 8;
  AttributionLbl.Font.Color := clGray;
  AttributionLbl.Caption := 'Citavi 6 中文语言包 · 社区汉化' + #13#10 +
    '@Martin-soaring-dev · CC BY-NC 4.0';
  AttributionLbl.Left := ScaleX(8);
  AttributionLbl.Top := WizardForm.NextButton.Top + WizardForm.NextButton.Height -
    AttributionLbl.Height;
  AttributionLbl.BringToFront;

  // 覆盖 Next 点击,使“留空=跳过”生效
  OldNextClick := WizardForm.NextButton.OnClick;
  WizardForm.NextButton.OnClick := @NextClick;
end;

// /SILENT 不触发 NextButton.OnClick;PrepareToInstall 在静默与交互安装前都会执行
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not IsCitaviBin(DirPage.Values[0]) then
  begin
    Result := 'Citavi 目录无效:未找到 Citavi.exe。请指定正确的 bin 目录。';
    Exit;
  end;
  // 仅在勾选安装 Word 时强制校验(与 NextClick 一致);取消勾选 = 明确跳过
  if ChkWord.Checked then
  begin
    if DirPage.Values[1] = '' then
    begin
      Result := 'Word 加载项目录为空。请指定 /WORDBIN= 有效目录,或去掉 Word 选项。';
      Exit;
    end;
    if not IsWordBin(DirPage.Values[1]) then
    begin
      Result := 'Word 加载项目录无效:未找到 SwissAcademic.Citavi.WordAddIn.dll,或该目录是 Citavi bin。';
      Exit;
    end;
  end;
end;