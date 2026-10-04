# 语言包待办与缺陷清单(Backlog)

> 分支:`v0.102`(基于 `origin/main`)。
> 本文档只针对 **语言包**;Add-On 见 [04-cn-metadata-addon.md](04-cn-metadata-addon.md)。
> 基线:v0.101 已发布;50 组 / 11,593 词条,已译 11,457(98.8%)。

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

- [ ] **人工校对全量译文**:术语、标点(全/半角)、简洁度、按钮长度。
- [ ] 复核 `中文==英文` 的 206 条:多数为 Lorem ipsum 占位帮助文本(`*_HelpText`)与
      `ISBN` / `ISBN / EAN` 等专名(正常);逐条确认是否有**应译未译**的真实界面文本。
- [ ] 复核“译文含 ≥3 个连续英文单词”的 132 处:排除技术术语/URL 后,补译明显遗漏处。
- [x] 复核反斜杠结构与英文不同的条目:`Strings.tsv:1493`
      `ResetAttachmentsFolderPath_DbServer` 已规范化为 `\\`(结果不变)。

---

## P3 — 验证与工程化

- [ ] **真实 Citavi 端到端验证**(核心):用本机已提取的 Citavi 6(见
      `%LOCALAPPDATA%\citavi6\extracted\program files\Citavi 6\bin`)安装 `dist/zh/`,
      确认语言菜单出现「中文」并可切换、重启后保持、切回英文正常。
      验证清单见 [02-roadmap.md](02-roadmap.md) 的「验证清单」。
- [ ] CI 增加对 [tools/Test-Translations.ps1](../tools/Test-Translations.ps1) 的 `-Strict` 调用
      (或把 P0-2 的新断言并入)。
- [ ] Citavi 升级后的**词条 diff 流程**:`Extract-Resources.ps1 -Diff` 只列缺失 key 并补译。
- [ ] 发布命名规范化:现有标签为 `v0.100` / `v0.101`,建议统一为 `v0.1.x`(需另议,避免重发)。

---

## 已确认正常(无需重复排查)

- HTML 实体:`EN` 与 `ZH` 0 处不一致。
- SmartFormat 单复数条件 `{n:...|...}`:0 处结构不一致。
- 未译 136 条全部为设计上不译:含 `|` 内部数据 106 + 纯数字 15 + 纯符号 11 + 空源 4。
- `dist/zh/` 6 个附属程序集与 `translations/` 同步(v0.101 构建时间一致)。
- CI `validate` 最近一次为 success。

---

## 验收(每个 P0/P1 修复后)

1. `pwsh ./tools/Test-Translations.ps1` → 0 错误;
2. `pwsh ./tools/Build-LanguagePack.ps1` → 生成 6 个附属程序集;
3. `pwsh ./tools/Test-LanguagePack.ps1 -CitaviBin <bin>` → 通过;
4. 抽查修复条目在 DLL 中反转义后的实际值(尤其 RTF 以 `{\rtf` 开头)。
