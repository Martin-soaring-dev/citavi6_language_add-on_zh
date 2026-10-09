# 语言包待办与缺陷清单(Backlog)

> 基线:v0.103 已发布;52 组 / 11,612 词条,已译 11,476(约 98.8%)。
> 本文档只针对 **语言包**;扩展插件不在本仓库范围内。
> Citavi 6 **官方已停止更新**,不再规划词条同步 / diff 流程。

## 0. 说明

优先级定义:

| 级别 | 含义 |
|---|---|
| **P0** | 正确性缺陷,会影响运行表现,必须修 |
| **P1** | 一致性/瑕疵,应修 |
| **P2** | 校对与打磨,可分批做 |
| **P3** | 验证与工程化,长期 |

---

## P0 — 正确性

> ✅ P0-1 / P0-2 已在 `v0.102` 修复。

### P0-1 8 条 RTF 字符串转义损坏 ✅ 已修复

翻译时把 TSV 规范要求的字面反斜杠 `\\` 压成了单个 `\`;构建脚本
`ConvertFrom-TsvField`([tools/Build-LanguagePack.ps1](../tools/Build-LanguagePack.ps1) 第 71–84 行)
会把 `\r` 反转义成**回车 CR**,导致字符串开头变成 `{<CR>tf1`,**不是合法 RTF**。

实测这 8 条反转义后均含 CR/LF:

| 文件 | 行 | key |
|---|---|---|
| `translations/SwissAcademic.Resources/SwissAcademic.Resources.ControlTexts.tsv` | 504 | `ActivateOfflineModeDialog_AttachmentsDescription` |
| 同上 | 1332 | `LicenseDialog_Problem` |
| `translations/SwissAcademic.Resources/SwissAcademic.Resources.Strings.tsv` | 1055 | `UpdateInstallationFullWritePermission` |
| 同上 | 1164 | `UpdateInstallationNoPermissionVista` |
| 同上 | 1276 | `SortKnowledgeItemsByModifiedBy` |
| 同上 | 2000 | `UpdateInstallationNoPermissionXP` |
| 同上 | 2237 | `SortKnowledgeItemsByCoreStatementTextCategory` |
| 同上 | 2365 | `SortKnowledgeItemsByReference` |

影响:许可对话框、离线模式附件说明、若干“更新安装权限 / 按…排序”富文本提示可能显示异常。

**修复方案(建议 A):**

1. 方案 A(推荐):把这 8 条译文里的字面反斜杠重新转义为 `\\`,但**保留**原本表示换行的
   `\r` / `\n` 序列不动。可用脚本按 EN 的转义结构校准,避免手改出错。
2. 方案 B(兜底):清空这 8 条译文 → 构建时回退英文(合法 RTF),先止血再补译。

> 注意:EN 中 RTF 控制字写作 `\\rtf1`、`\\ansi`…,换行写作 `\r\n`(单反斜杠),两者语义不同,不能一律翻倍。

### P0-2 校验脚本覆盖不足 ✅ 已修复

[tools/Test-Translations.ps1](../tools/Test-Translations.ps1) 目前只校验列数、key 重复、`{n}` 占位符,
**不校验反斜杠转义、RTF/HTML 标签**,所以 P0-1 逃过了 CI。

已增加断言:

- 反转义后,若 EN 以 `{\rtf` 开头,ZH 也必须以 `{\rtf` 开头(错误);
- 反斜杠转义规范:奇数长度反斜杠串后非 `r`/`n`/`t` 者报警告(字面反斜杠应写成 `\\`);
- 原「译文以反斜杠结尾」误报改为奇偶判别。

> 待办:HTML 标签一致性校验(见 P2)。

---

## P1 — 一致性

> ✅ P1-1 / P1-2 / P1-3 已在 `v0.102` 处理。

### P1-1 术语/标点不统一(7 组) ✅ 已统一

同一英文原文对应多种中文写法。已统一为单字符省略号 `…`(U+2026),并写入
[03-translation-guide.md](03-translation-guide.md) 第 5 条:

| 英文 | 统一后 |
|---|---|
| `Loading...` / `Loading…` | `正在加载…` |
| `Saving...` / `Saving…` | `正在保存…` |
| `More...` / `More…` | `更多…` |
| `Attempting to reconnect...` / `Attempting to reconnect…` | `正在尝试重新连接…` |
| `Waiting to reconnect...` / `Waiting to reconnect…` | `正在等待重新连接…` |
| `Search document...` / `Search document…` | `搜索文档…` |
| `Retrieve from the Citavi server…` | `从 Citavi 服务器获取…` |

### P1-2 `BibTeXAutoExportNotSuccess` 少一个换行 ✅ 已修复

`Strings.tsv:1098`:改为与 `BibTeXAutoExportSuccess` 相同的结构
`BibTeX 文件\r\n{0}\r\n无法创建。`。

### P1-3 校验警告 ✅ 已处理

`SwissAcademic.Resources.WebLabelsAccount.tsv:19` `PasswordContainsInvalidChars`
结尾为 4 个反斜杠(偶数,合法)。已把 `Test-Translations.ps1` 的「结尾反斜杠」判断改为
奇偶判别,该误报自然消失,无需白名单。

---

## P2 — 校对与打磨

> 🟡 已做一轮**基于语境**的术语统一与误译修正(`v0.102`);全量逐条校对仍在继续。

- [x] **术语一致性**:按语境统一 20+ 组术语(题录/关键字/脱机/批注/过滤/媒介/父文献/单席位…),
      决策已写入 [03-translation-guide.md](03-translation-guide.md) 术语表。
- [x] **语境误译**:修正约 60 处一词多义与时态/搭配错误
      (如 `Minutes→分钟`、`Reporter→判例汇编`、`Assignee→受让人`、`Manual→手册`、`Editor→编者`;
      `Evaluation` 字段统一「评价」,动词/试用版保留「评估」)。
- [x] 复核 `中文==英文` 206 条:多数为 Lorem ipsum 占位帮助文本(`*_HelpText`)与 `ISBN` 等专名,**判定保留**。
- [x] 复核「含 ≥3 连续英文单词」132 处:除产品名/HTML/代码外,**无整句漏译**。
- [x] 反斜杠结构不同条目已规范化。
- [x] **长尾资源组逐条通读**:`WordProcessorResources`(行距/图元文件/霍夫曼符号等)、
      `CRM`、`TeX`、`WebLabelsCitaviSpace/Offline/HelpTexts`、`LanguagesAndCultures` 等;
      并统一「帐户→账户」。
- [x] **标点全/半角统一**:中文相邻的半角 `, ; : ? !` 与句末 `.` 统一为全角,`...` → `…`。
- [x] **按钮/标签长度抽查**:0 条超长候选。

---

## P3 — 验证与工程化

- [x] **真实 Citavi 端到端验证**(核心):语言菜单出现「中文」、可切换、重启后保持、切回英文正常。
- [x] CI 对 [tools/Test-Translations.ps1](../tools/Test-Translations.ps1) 使用 `-Strict`,
      并校验 **SmartFormat 分支结构** 与 **HTML 标签集合**(白名单,忽略 `<Project name>` 之类伪标签)。
- [x] ~~Citavi 升级后的词条 diff 流程~~ —— **不做**:官方已停止更新,无新增词条预期。
- [ ] 发布命名规范化:现有标签为 `v0.100` / `v0.101`,建议统一为 `v0.1.x`(需另议,避免重发)。

---

## 快速帮助(Quick Help / Custom Help)

Citavi 右侧「快速帮助」原为**联网**内容(官方无中文)。本语言包通过本地覆盖机制,由安装器写入
`文档\Citavi 6\Custom Help\<HelpContext>.<lang>.rtf`(**622 个主题**,无需管理员)。

机制与命名(依据反编译 `CitaviHelpBox` / `HelpPathHelper`):

- 普通对话框: `<HelpContext>.zh.rtf`
- 按**文献类型**变化(仅「选择文献类型」对话框): `<HelpContext>-<ReferenceTypeId>.zh.rtf`(35 个类型文件)
- 查找顺序(带类型时): `<ctx>-<type>.zh.rtf` → `<ctx>-<type>.en.rtf` → `<ctx>.zh.rtf` → `<ctx>.en.rtf` → `<ctx>.rtf`
- 非 ASCII 一律写 `\uNNNN?` 转义。

### 已知限制:运行时动态/联网帮助无法覆盖

少数对话框**不读本地 Custom Help**,而是运行时**直接联网**取正文、或在本地拼接动态内容后
`helpBox.SetHelpText(...)` 注入。语言包机制**无法**覆盖这些(且官方服务对 `uiCulture=zh` 仍返回英文):

| 对话框 | 机制 |
|---|---|
| 按 ID 检索文献 (`LookupReferenceIdentifierDialog`) | 直接调用 `FindHelpPathOnlineAsync` |
| 查找馆藏位置 (`LookupLocationsDialog`) | 直接调用 `FindHelpPathOnlineAsync` |
| 编辑/收藏引文样式 (`CitationStyleListDialogEx` / `CitationStyleFavoriteDialog`) | 样式文件 `.ccs` 内 `<HelpContext>`,按 `<Culture>` 分语言(缺 `_zh` 变体) |
| 在线检索列表 (`OnlineSearchDialogEx`) | 由在线目录定义动态拼接 |
| 导入/导出向导凭据 (`ExportWizardDialog` 等) | 动态 `TransformerHelpContext` |

> 这些对话框内**本地可翻译**的部分(如「单击此处选择其他目录/库」`ShowIsbnTransformerDialogHelpContextPart`、
> `LookupLocations_*` 等)已中文化;仅**正文**来自联网/样式文件,故保持英文。
> 若需覆盖联网正文,唯一途径是把 `Citavi.exe.config` 的 `BackOfficeUrl` 指向本地帮助服务器(并代理其余请求)
> —— 会改动 Citavi 原始配置、需常驻服务、影响在线功能,**暂不采用**。

---

## 已确认正常(无需重复排查)

- HTML 实体:`EN` 与 `ZH` 0 处不一致。
- SmartFormat 单复数条件 `{n:...|...}`:0 处结构不一致。
- 未译 136 条全部为设计上不译:含 `|` 内部数据 106 + 纯数字 15 + 纯符号 11 + 空源 4。
- `dist/zh/` 7 个附属程序集与 `translations/` 同步。
- CI `validate` 最近一次为 success。

---

## 验收(每个 P0/P1 修复后)

1. `pwsh ./tools/Test-Translations.ps1` → 0 错误;
2. `pwsh ./tools/Build-LanguagePack.ps1` → 生成 7 个附属程序集;
3. `pwsh ./tools/Test-LanguagePack.ps1 -CitaviBin <bin>` → 通过;
4. 抽查修复条目在 DLL 中反转义后的实际值(尤其 RTF 以 `{\rtf` 开头)。
