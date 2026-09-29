# 实施计划与流水线设计

状态:🟡 **流水线已可用** —— 提取 / 分片 / 合并 / 构建 / 测试 / 打包脚本均已实现;翻译进行中(改用模型按分片翻译)。

---

## 总体流程

```
[Citavi 安装目录]
      │  Extract-Resources.ps1
      ▼
translations/*.tsv        (key ⇥ English ⇥ 中文)   ← 机翻初稿 + 人工校对
      │  Build-LanguagePack.ps1
      ▼
build/*.resources  →  csc.exe  →  dist/zh/*.resources.dll (6 个)
      │  Install-LanguagePack.ps1
      ▼
C:\Program Files (x86)\Citavi 6\bin\zh\
```

## 阶段划分

### 阶段 1 — 提取(Extract-Resources.ps1)

从 Citavi 安装目录读取**中性(英文)资源**,导出为便于翻译的 TSV。

输入:`-CitaviBin "C:\Program Files (x86)\Citavi 6\bin"`

输出:`reference/<Assembly>/<ResourceGroup>.tsv`,并复制到 `translations/`。

- 用 `System.Reflection.Assembly` + `System.Resources.ResourceReader` 读取。
- 跳过纯非文本资源组(如 `Icons`)。
- 非字符串条目(如 `int`)原样保留,不参与翻译。
- `reference/` 不入库;`translations/` 入库。

### 阶段 2 — 翻译

- 按资源组拆分文件,便于分工与 review。
- 主流程:**分片 + 模型/译员翻译**
  1. `Prepare-TranslationShards.ps1` 把待翻译词条切成 `reference/shards/shard-XXX.tsv`(`<id>\t<原文>`);
  2. 每个分片由译员/子代理翻译,产出 `shard-XXX.zh.tsv`(`<id>\t<中文>`);
  3. `Merge-TranslationShards.ps1` 校验占位符后合并回 `translations/`。
  - 用数字 id 作键,避免译员抄错英文原文;分片流程可反复执行,只切未翻译的词条。
- 备用通道:免费 Google 接口(`Translate-Draft.ps1`)或本地 MCP 翻译服务(`mcp_translate.py`);
  免费接口在批量下会被限流(429/403),不作为主通道。
- 跳过项:含 `|` 且**不含** `{n:...}` 条件的内部数据(多语言占位符词表、文件过滤器等)
  **不翻译**,否则会改变 Citavi 的匹配行为。
- 注意:.NET **SmartFormat 单复数条件** `{0:1 reference|{0} references}` 属于界面文本,
  必须翻译,且要完整保留 `{n:` / `|` / 结尾 `}` 结构。
- 未翻译/留空的条目在构建时自动回退英文。
- 规范见 [03-translation-guide.md](03-translation-guide.md)。

### 阶段 3 — 构建(Build-LanguagePack.ps1)

1. 读取 `translations/*.tsv`,用 `System.Resources.ResourceWriter` 生成 `.resources`,
   资源命名 `<基名>.zh.resources`。
2. 为每个目标程序集生成 `AssemblyInfo.cs`(`AssemblyVersion` + `AssemblyCulture("zh")`)。
3. 调用 .NET Framework 自带的 `csc.exe` 编译:
   - 输出文件名 = `<父程序集名>.resources.dll`
   - 6 个目标:`Citavi`、`SwissAcademic`、`SwissAcademic.Citavi`、`SwissAcademic.Controls`、
     `SwissAcademic.Resources`、`SwissAcademic.WordProcessing`
4. 产物输出到 `dist/zh/`。

要点:
- **不需要** Visual Studio / .NET SDK,`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` 即可。
- 版本号必须与父程序集一致(见 [01-mechanism.md](01-mechanism.md) §8)。
- 无强命名,无需签名。

### 阶段 4 — 安装 / 卸载(Install-LanguagePack.ps1)

- 将 `dist/zh/` 复制到 `<CitaviBin>\zh\`(需要管理员权限)。
- 可选 `-Uninstall` 删除目录。
- 安装后提示:工具 → 语言 → 中文。

### 阶段 5 — 版本同步(后续)

Citavi 升级后新增字符串需补翻:

```
Extract-Resources.ps1 -Diff   →  只列出 translations 中缺失的 key
```

---

## 待办清单

- [x] `tools/Extract-Resources.ps1` — 实现提取(实测 50 组 / 11,593 条)
- [x] `tools/Prepare-TranslationShards.ps1` — 分片
- [x] `tools/Merge-TranslationShards.ps1` — 合并回填
- [x] `tools/Build-LanguagePack.ps1` — 实现构建(输出 6 个附属程序集)
- [x] `tools/Test-Translations.ps1` — 译文格式/占位符校验
- [x] `tools/Test-LanguagePack.ps1` — 不启动 Citavi 的解析验证
- [x] `tools/Install-LanguagePack.ps1` — 实现安装/卸载
- [x] `tools/Package-Release.ps1` — 生成分发 zip
- [x] `tools/Setup-TranslateMcp.ps1` + `tools/mcp_translate.py` — 接入 MCP 翻译服务(备用)
- [x] `translations/` — 生成英文源文件骨架
- [ ] 用模型完成全量翻译(8,078 条唯一原文,分片进行中)
- [ ] 人工校对(术语、占位符、长度)
- [ ] 在真实 Citavi 中端到端验证(语言菜单出现「中文」)
- [x] CI:校验 TSV 格式、占位符一致、构建产物、打包 zip(Artifact)
- [x] 自动发布:推送 `v*` 标签自动创建 GitHub Release 并附 zip
- [ ] Citavi 升级后的词条 diff 流程

## 已实现的脚本行为

| 脚本 | 输入 | 输出 |
|---|---|---|
| `Extract-Resources.ps1` | Citavi `bin\` | `translations/*.tsv`(保留已有译文)、`reference/nonstring/*.tsv`、`reference/manifest.json` |
| `Prepare-TranslationShards.ps1` | `translations/` | `reference/shards/shard-XXX.tsv`、`index.json`、`manifest.json` |
| `Merge-TranslationShards.ps1` | `reference/shards/*.zh.tsv` | 合并到 `reference/mt-cache.json` 并回填 `translations/` |
| `Translate-Draft.ps1` | `translations/` | (备用)免费 Google 机翻初稿 |
| `mcp_translate.py` | `translations/` | (备用)经 `translate-mcp-server` 批量翻译 |
| `Setup-TranslateMcp.ps1` | — | 安装/启动本地 MCP 翻译服务 |
| `Build-LanguagePack.ps1` | `translations/` | `dist/zh/*.resources.dll`(6 个) |
| `Test-Translations.ps1` | `translations/` | 格式/占位符校验结果(退出码 0/1) |
| `Test-LanguagePack.ps1` | `dist/zh/` + Citavi `bin\` | 控制台验证结果(退出码 0/1) |
| `Install-LanguagePack.ps1` | `dist/zh/` + Citavi `bin\` | `bin\zh\`;`-Uninstall` 删除 |
| `Package-Release.ps1` | `dist/zh/` | `dist/citavi6-zh-v<版本>.zip` |

## 验证清单(端到端)

1. `bin\zh\` 存在且含 6 个 `*.resources.dll`(其中必须有 `SwissAcademic.Resources.resources.dll`)。
2. 启动 Citavi → 工具 → 语言,出现「中文」。
3. 选择「中文」→ 界面切换(部分需重启)。
4. 重启后仍为中文(设置已持久化)。
5. 切回英文正常,无异常日志。

## 已知风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| 词条量大(≈11.7k) | 全量翻译工作量大 | 分批、优先高可见部分;英文回退保证可用 |
| Citavi 升级 | 新增/改动词条 | 版本同步脚本 + 定期 diff |
| 长文本/富文本 | 含 HTML、`{0}` 占位符 | 翻译规范强制保留占位符;CI 校验 |
| 版式溢出 | 中文较短一般无碍,个别按钮可能变长 | 抽查截图 |
| 版权 | 不得分发 Citavi 原始二进制 | `.gitignore` 排除 `reference/`;仅提交译文 |
