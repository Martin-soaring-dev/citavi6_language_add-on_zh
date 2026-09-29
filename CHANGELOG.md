# 更新日志

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
