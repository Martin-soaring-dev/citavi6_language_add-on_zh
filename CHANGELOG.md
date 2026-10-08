# 更新日志

## v0.103

**品牌视觉接入分发物**
- 新增 `tools/Build-BrandAssets.ps1`:用 headless Chromium 把 `docs/brand/simple/svg/` 光栅化为安装包位图,
  再用 System.Drawing 组装多尺寸 ICO;无 npm/pip 依赖,中间产物写到 `build/brand/`(不入库)。
- 新增入库位图 `docs/brand/simple/export/win/`:`setup.ico`(16/24/32/48/64/128/256)、
  `wizard-image.png`(656×1256)、`wizard-small.png`(318×318)、`logo-symbol.png`(456×295)。
- `Citavi6-zh.iss` 挂载 `SetupIconFile` / `WizardImageFile` / `WizardSmallImageFile`,并设
  `UninstallDisplayIcon={uninstallexe}` —— 卸载项图标复用内嵌的 SetupIconFile,**不往 Citavi 目录多放任何文件**。
- `Build-Installer.ps1` 编译前校验三份安装包资产,缺失即报错(而不是等 ISCC 失败)。
- ZIP 新增 `assets\`(`setup.ico` + `logo-symbol.png`);`Install-Gui.ps1` 窗体加图标与头部徽标,
  资产缺失时静默降级不带图。
- 图形资产许可明确为与代码一致的 **CC BY-NC 4.0**(`VISUAL_IDENTITY.md` §10.2);`setup.ico` 的 16/24 帧
  由 512 图标直接缩放,16 px 简化型仍未绘制(§06 记录该状态)。
- `.gitattributes` 增加 `*.png/*.ico/*.bmp binary`。

**许可页与作者署名(防盗用举证)**
- 新增 `tools/installer/license.zh.txt`(使用条款)与 `infoafter.zh.txt`(装完提示页),
  由 `.iss` 的 `LicenseFile` / `InfoAfterFile` 引用;`.txt` 必须是 UTF-8/UTF-16LE,换行用
  `.gitattributes` 钉成 CRLF,`Build-Installer.ps1` 编译前校验存在性与 CRLF。
- Setup.exe 必须选「我接受协议」才能继续;许可页的接受/拒绝文案覆盖为中文
  (`[Messages] LicenseAccepted` / `LicenseNotAccepted` / `LicenseLabel3`),向导其余文案仍为英文。
- 作者信息三处常驻:`[Messages] BeveledLabel`(每个向导页底部)、`AppPublisherURL` /
  `AppSupportURL` / `AppUpdatesURL`(「应用和功能」)、`VersionInfo*` 文件属性
  (Company / Copyright(含 CC BY-NC 与仓库地址)/ Description / ProductName / Version)。
- ZIP:「安装说明.txt」增「许可与作者」段,并随附「使用条款.txt」。
- `Install-Gui.ps1` 加同意门:未同意不得安装(卸载不需同意),「查看条款…」弹模态框显示同一条款;
  条款文件缺失时退化为要点提示。复选框与按钮放进按钮行既有空档,不动原排版。
- README「⚠️ 免责声明」→「⚠️ 免责声明与许可」,补许可、作者与唯一官方分发渠道。

## v0.102

**语言包校正**
- 修复 8 条 RTF 字符串转义损坏(字面反斜杠被压成单个,构建时 `\r` 被反转义为回车,RTF 失效)。
- `Test-Translations.ps1` 增强:新增加「RTF 反转义后须以 `{\rtf` 开头」「反斜杠转义规范」校验。
- 统一术语:`题录→文献`、`关键字→关键词`、`脱机→离线`、`批注→注释`、`过滤器→筛选器`、
  `出版商→出版社`、`备注→笔记`、`媒介→存储介质`、`上级文献/父文献/父题录→父级参考文献`、
  `馆藏地/馆藏位置→位置`、`丛书名称→丛书标题`、`核心论述→核心陈述`、`兑换码→优惠券代码`、
  `单机(版/许可证)/按席位→单席位`。
- 按语境修正约 60 处误译,例如 `Minutes → 分钟`、`Reporter → 判例汇编`、`Assignee → 受让人`、
  `Reader(有声书) → 朗读者`、`Run time → 片长`、`Manual → 手册`、`Middle(重要性) → 中`、
  `Editor(字段) → 编者`、`Open tasks → 未完成任务`、`Contribution → 篇章`;`Evaluation` 字段统一为「评价」,
  但动词/试用版(`评估其频率`、`评估版已过期`)保留「评估」。
- 术语表(见 `docs/03-translation-guide.md`)已扩充。
- 新增第 7 个附属程序集 `SwissAcademic.Citavi.WordAddIn`(Word 加载项的 `_zh` 帮助与异常字符串),
  使 Word 加载项在中文环境下显示中文帮助。
- 新增一键安装器 `安装.vbs`(图形界面,启动即请求管理员权限)与 `Install-Toolkit.ps1`(CLI):自动检测 Citavi、Word 加载项与「快速帮助」目录、
  预览计划、检测冲突进程(显示名称+PID 并弹窗)后覆盖安装,完成弹窗;支持 `-WhatIf`/`-Uninstall`。
- 新增 **单文件安装程序**(Inno Setup):`tools/Build-Installer.ps1` + [`tools/installer/Citavi6-zh.iss`](../tools/installer/Citavi6-zh.iss)
  产出 `Citavi6-zh-Setup-v<版本>.exe`——Pascal 脚本自动探测 Citavi/Word/快速帮助目录,自定义页选择组件,写入「应用和功能」卸载项,支持 `/VERYSILENT` 与 `/CITAVIBIN=`/`/WORDBIN=`/`/HELPDIR=` 覆盖。
- 新增 **Citavi 内置「快速帮助」中文**:622 个主题。该帮助原为**联网**内容(官方无中文),
  现通过本地覆盖机制 `Documents\Citavi 6\Custom Help\<HelpContext>.zh.rtf` 提供中文;安装器一并安装。
  其中「选择文献类型」对话框的帮助**随所选类型变化**,按文件名规则 `<HelpContext>-<TypeId>.zh.rtf`
  提供 35 个类型文件(否则所有类型都会显示同一段)。
- 安装器新增「快速帮助目录」目标(自动定位 `Custom Help`,亦可手动覆盖:`-CustomHelpDir` / GUI 文本框)。
- **长尾资源组逐条校对**:`WordProcessorResources`(行距选项、图元文件、霍夫曼符号、重启标记等)、
  `CRM`、`TeX`、`WebLabelsCitaviSpace/Offline/HelpTexts`、`LanguagesAndCultures` 等;
  并统一「帐户 → 账户」。
- **标点全/半角统一**:中文相邻的半角 `, ; : ? !` 与句末 `.` 统一为全角,`...` → `…`。
- **按钮/标签长度抽查**:无超长候选。

验证:`Test-Translations` 0 错误 0 警告(-Strict);构建 7 个附属程序集;`Test-LanguagePack` 通过。

## v0.1(第一版)

**语言包**
- 新增 `zh` 简体中文语言包(6 个附属程序集)。
- 覆盖 `SwissAcademic.Resources` 等 6 个程序集、50 个资源组、11,593 条词条。
- 含 `|` 的多语言占位符/正则等内部数据(247 条)不翻译,保证 Citavi 匹配行为不变。
- 未翻译词条运行时自动回退英文。

**机制逆向**
- 确认 Citavi 6 通过扫描 `bin\` 子目录发现语言包:目录名须匹配 `^([A-Z][a-z]-)?[a-z]{2}(-[A-Z]{2,3})?$`
  且包含 `SwissAcademic.Resources.resources.dll`;因此目录名用 `zh`(不能是 `zh-Hans`)。
- 确认程序集均未强命名,可直接生成附属程序集;详见 `docs/01-mechanism.md`。

**工具链**
- `Extract-Resources.ps1` 提取英文源(50 组 / 11,593 条);
- `Prepare-TranslationShards.ps1` / `Merge-TranslationShards.ps1` 分片翻译与合并回填;
- `Build-LanguagePack.ps1` 构建附属程序集(`csc.exe`,无需 Visual Studio);
- `Test-Translations.ps1` 译文校验;`Test-LanguagePack.ps1` 解析验证;
- `Install-LanguagePack.ps1` 安装/卸载;`Package-Release.ps1` 打包;
- `Setup-TranslateMcp.ps1` + `mcp_translate.py` 接入本地 MCP 翻译服务(备用通道);
- `Translate-Draft.ps1` 免费 Google 接口机翻(备用通道,受 429/403 限流)。

**翻译**
- 采用"分片 + 模型翻译"产出初稿(33 个分片,8,078 条唯一原文)。
- 译文仍为**初稿**,欢迎提交校对 PR。
