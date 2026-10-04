# 更新日志

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
- 新增一键安装器 `Install-Toolkit.ps1` / `安装.cmd`:自动检测 Citavi 与 Word 加载项目录、
  预览计划、检测冲突进程(显示名称+PID 并弹窗)后覆盖安装,完成弹窗;支持 `-WhatIf`/`-Uninstall`。
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
