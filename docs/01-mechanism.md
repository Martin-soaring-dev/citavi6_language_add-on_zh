# Citavi 6 语言机制详解

本文记录了 Citavi 6 界面语言的全部机制、反编译证据与实现约束,是制作中文语言包的技术依据。

分析对象:**Citavi 6.20.0.0**(MSI `Citavi6Setup.msi`,直链 `https://citavibackoffice.blob.core.windows.net/setup/Citavi6Setup.msi`)。

---

## 1. 结论速览

- Citavi 6 的界面文字使用 **.NET 附属程序集** 实现国际化,而非自定义格式。
- 语言菜单由 **扫描安装目录 `bin\` 的子目录** 动态生成,没有硬编码的语言白名单。
- 因此:**新增一个 `bin\zh\` 目录(含 `SwissAcademic.Resources.resources.dll`),中文即出现在语言菜单中。**
- 所有 Citavi 程序集**均未强命名**,可以自由生成我们自己的附属程序集,无需密钥。

## 2. 安装目录中的语言包

`bin\` 下的语言子目录:

```
bin\
├─ de\  es\  fr\  it\  nl\  pl\  pt\  ru\  sv\
└─ x64\  x86\  PDFNet\
```

`de\`(以及其他语言目录)内容:

```
Citavi.resources.dll
SwissAcademic.Citavi.resources.dll
SwissAcademic.Controls.resources.dll
SwissAcademic.resources.dll
SwissAcademic.Resources.resources.dll
SwissAcademic.WordProcessing.resources.dll
```

即:每个语言包对应 **7 个附属程序集**。

> `nl / ru / sv` 目录只含 `SwissAcademic.resources.dll` 与 `SwissAcademic.WordProcessing.resources.dll`(第三方/Word 处理相关),并非完整界面语言。

## 3. 语言列表如何生成(反编译证据)

`SwissAcademic.Citavi.dll` → `CitaviEngine.FindInstalledCultures()`:

```csharp
private static void FindInstalledCultures()
{
    _installedUICultures = new List<CultureInfo>();
    _installedUICultures.Add(CultureInfo.GetCultureInfo("en"));
    DirectoryInfo[] directories =
        new FileInfo(Assembly.GetExecutingAssembly().Location).Directory.GetDirectories();
    foreach (DirectoryInfo directoryInfo in directories)
    {
        if (_cultureNameRegex.IsMatch(directoryInfo.Name) &&
            directoryInfo.GetFilesSafe("SwissAcademic.Resources.resources.dll").Length != 0)
        {
            try {
                CultureInfo cultureInfo = CultureInfo.GetCultureInfo(directoryInfo.Name);
                _installedUICultures.Add(cultureInfo);
            } catch (Exception exception) { /* 记录遥测 */ }
        }
    }
}
```

其中

```csharp
private static Regex _cultureNameRegex = new Regex("^([A-Z][a-z]-)?[a-z]{2}(-[A-Z]{2,3})?$",
                                                  RegexOptions.Compiled);
```

**要点**

- `Assembly.GetExecutingAssembly().Location` 指向 `SwissAcademic.dll`,即 `bin\` → 语言目录必须放在 `bin\` 下。
- 目录必须包含文件名精确为 `SwissAcademic.Resources.resources.dll` 的文件。
- 正则**区分大小写**,接受:
  - `xx`(如 `de`、`fr`、`zh`)✅
  - `xx-XX`、`xx-XXX`(如 `pt-BR`、`zh-CN`、`zh-CHS`)✅
  - `zh-Hans` ❌(第二段要求 2–3 个大写字母,`Hans` 不匹配)
- 始终包含 `en`(中性/英文)。

## 4. 语言菜单

`Citavi.exe` → `StartForm` / `MainForm` 的 `ToolsLanguage` 下拉:

```csharp
foreach (CultureInfo culture in CitaviEngine.InstalledUICultures.OrderBy(item => item.NativeName))
    listTool.ListToolItems.Add(culture.Name, culture.NativeName.ToInitialUpper());
```

- 菜单显示名 = `CultureInfo.NativeName`。
  - `zh` → `中文`
  - `zh-CN` → `中文(中国)`
- 本项目选择 `zh`,以兼容任意中文系统(见 §7)。

## 5. 切换语言时发生什么

点击语言项(`PerformCommand("UICultures")`):

```csharp
CultureInfo cultureInfo = CultureInfo.GetCultureInfo(e.ListToolItem.Key);
Program.Engine.Settings.General.UICulture = cultureInfo;   // 见 GeneralSettings
// 随后 Localize();部分界面立即生效,另一些需重启
```

`GeneralSettings.UICulture`:

```csharp
public CultureInfo UICulture
{
    get {
        var c = GetValue<CultureInfo>("UICulture");
        if (c == null) {
            // 首次运行:按系统 UI 语言匹配已安装语言,否则 en
            string name = Thread.CurrentThread.CurrentUICulture.Name;
            var match = CitaviEngine.InstalledUICultures.FirstOrDefault(i => i.Name == name)
                     ?? CitaviEngine.InstalledUICultures.FirstOrDefault(i => i.Name == Thread.CurrentThread.CurrentUICulture.TwoLetterISOLanguageName)
                     ?? CultureInfo.GetCultureInfo("en");
            c = match; SetValue(c, "UICulture");
        }
        return c;
    }
    set {
        // 值必须在 InstalledUICultures 中,否则回退 en
        var c = CitaviEngine.InstalledUICultures.FirstOrDefault(i => i.Name == value?.Name)
             ?? CitaviEngine.InstalledUICultures.FirstOrDefault(i => i.Name == value?.TwoLetterISOLanguageName)
             ?? CultureInfo.GetCultureInfo("en");
        SetValue(c, "UICulture");
    }
}

protected override void OnSettingsLoaded(...) {
    Thread.CurrentThread.CurrentUICulture = UICulture;
    CultureInfo.DefaultThreadCurrentUICulture = UICulture;
}
protected override void OnPropertyChanged(...) {
    case "UICulture":
        Thread.CurrentThread.CurrentUICulture = UICulture;
        CultureInfo.DefaultThreadCurrentUICulture = UICulture;
        break;
}
```

**结论**:设置 `CultureInfo.CurrentUICulture` 后,标准 .NET 资源查找会自动加载对应 `bin\<culture>\` 下的附属程序集。

## 6. 资源清单(需要翻译的字符串)

由 `tools/Extract-Resources.ps1` 实测(可翻译的字符串条目):

| 程序集(中性) | 资源组 | 字符串数 | 备注 |
|---|---|---|---|
| **SwissAcademic.Resources.dll** | 26 | **11,203** | 界面主体 |
| SwissAcademic.Controls.dll | 1 | 237 | Word 处理器字符串 |
| SwissAcademic.Citavi.dll | 3 | 108 | |
| Citavi.exe | 18 | 39 | 其余为 WinForms 设计器布局常量(键为空,非文本) |
| SwissAcademic.dll | 1 | 5 | |
| SwissAcademic.WordProcessing.dll | 1 | 1 | |
| SwissAcademic.Citavi.WordAddIn.dll | 2 | 19 | Word 加载项:帮助 `_zh` + 异常对话框 |
| **合计** | **52** | **11,612** | |

> `SwissAcademic.Citavi.WordAddIn.dll` 的 Ribbon/对话框字串已包含在主体的 `WordAddIn` 组;
> 其自带的 `Properties.Help`(按语言后缀的 RTF 帮助)与 `ExceptionDialog` 由第 7 个附属程序集提供 `_zh`。

`SwissAcademic.Resources.dll` 各组明细:

| 资源组 | 条目数 |
|---|---|
| Strings | 2367 |
| ControlTexts | 1941 |
| Tools | 1344 |
| Enums | 973 |
| WebLabels | 737 |
| ReferenceTypeLabels | 686 |
| StyleEditor | 670 |
| WebLabelsAccount | 422 |
| DbServerManager | 370 |
| Entities | 301 |
| WebLabelsCommon | 296 |
| WordAddIn | 279 |
| FormTexts | 176 |
| LanguagesAndCultures | 169 |
| WebLabelsShop | 106 |
| WebLabelsStart | 88 |
| zzNotTranslated.SupportInformationStrings | 71 |
| FileDialogFilters | 50 |
| TeX | 40 |
| SpecialChars | 36 |
| CRM | 31 |
| WebLabelsHelpTexts | 20 |
| zzNotTranslated.CodeResources | 10 |
| WebLabelsCitaviSpace | 10 |
| WebLabelsOffline | 6 |
| zzNotTranslated.Settings.Settings | 4 |
| **合计** | **11,203** |

> - `zzNotTranslated.*` 是官方自己都没翻译的组,优先级最低。
> - `SwissAcademic.Resources.CRMde`(官方德语邮件模板)与 `Icons`(非文本)已跳过。
> - Citavi.exe 等程序集内嵌资源中有大量**键为空**的 WinForms 设计器条目(布局常量/图像),
>   它们不可翻译也无需处理——运行时自动使用中性值。

## 7. 命名与兼容性:`zh` vs `zh-CN`

- 语言目录名正则只接受 `xx` / `xx-XX`。
- 采用 **`zh`**(中性中文):
  - 语言菜单显示「中文」。
  - `GeneralSettings.UICulture` 的匹配逻辑:先按完整名(`zh-CN` / `zh-Hans` / `zh-TW` …),再按 `TwoLetterISOLanguageName`(都是 `zh`)匹配。因此 **任何 `zh-*` 系统都能匹配到 `zh`**。
  - 与官方现有语言目录(全部是 `de`/`fr` 等中性名)风格一致。
- 代价:`zh-TW`(繁体)用户也会匹配到简体包。对简体语言包可接受。

## 8. 附属程序集的技术约束

| 约束 | 值 |
|---|---|
| 强命名 | 无(PublicKeyToken 为空)→ 无需签名 |
| 程序集名 | 必须为 `<父程序集名>.resources`,如 `SwissAcademic.Resources.resources` |
| 程序集版本 | 必须与父程序集一致(见下表) |
| `AssemblyCulture` | `zh` |
| 资源命名 | `<资源基名>.zh.resources`,如 `SwissAcademic.Resources.Strings.zh.resources` |
| 缺失词条 | 按 key 逐级回退到中性(英文)→ 支持增量翻译 |

父程序集版本:

| 父程序集 | AssemblyVersion |
|---|---|
| Citavi.exe | 5.8.0.0 |
| SwissAcademic.dll | 5.8.0.0 |
| SwissAcademic.Citavi.dll | 5.8.0.0 |
| SwissAcademic.Controls.dll | 5.8.0.0 |
| SwissAcademic.WordProcessing.dll | 5.8.0.0 |
| SwissAcademic.Resources.dll | 6.0.0.0 |

编译方式(无需 Visual Studio):

```
csc.exe /nologo /target:library /out:zh\SwissAcademic.Resources.resources.dll ^
        /resource:build\SwissAcademic.Resources.Strings.zh.resources ^
        ... /resource:... ^
        AssemblyInfo.SwissAcademic.Resources.cs
```

`AssemblyInfo.*.cs` 内容:

```csharp
using System.Reflection;
[assembly: AssemblyVersion("6.0.0.0")]   // 对应父程序集版本
[assembly: AssemblyCulture("zh")]
```

## 9. 设置文件位置(排障用)

- 用户设置目录:`%APPDATA%\Swiss Academic Software\Citavi 6\<SettingsFolder>`
- 启动设置:`%APPDATA%\Swiss Academic Software\Citavi 6\StartupSettings6.xml`
- 语言保存在 GeneralSettings 的 `UICulture` 字段中,序列化为 XML/DataContract。

若语言异常,可关闭 Citavi 后删除/修改该设置中的 `UICulture`,重启后会重新按系统语言匹配。

## 10. 复现本分析

```powershell
# 下载并解包安装包(不安装)
Invoke-WebRequest "https://citavibackoffice.blob.core.windows.net/setup/Citavi6Setup.msi" -OutFile Citavi6Setup.msi
msiexec /a Citavi6Setup.msi /qn TARGETDIR="$PWD\extracted"

# 反编译
dotnet <ilspycmd>/ilspycmd.dll -o src "extracted\program files\Citavi 6\bin\SwissAcademic.Citavi.dll"
```
