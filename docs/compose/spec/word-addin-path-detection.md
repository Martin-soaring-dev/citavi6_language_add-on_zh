---
feature: word-addin-path-detection
status: delivered
updated: 2026-10-09
branch: fix/word-addin-path-detection
commits: dba5190..74da0c8
---

# Word 加载项路径探测统一与安装 UX 修正

## Report

**What was built** — Word 加载项目录探测在 Setup.exe 与三套 PowerShell 安装器上统一为同一契约：判定必须含 `SwissAcademic.Citavi.WordAddIn.dll` 且不含 `Citavi.exe`；探测顺序为显式覆盖 → 注册表（Word `InstallRoot` / ClickToRun，含 64 位视图）→ 双 Program Files 约定路径 → `StartupSettings6.xml` → 文件系统。勾选失败不再回退 Citavi bin；`PrepareToInstall` 覆盖 `/SILENT` 校验；`RefreshPaths` 不覆盖命令行路径。共享实现落在 `tools/lib/Resolve-WordAddInPath.ps1`，ZIP 打包携带。

**Verification** — `pwsh ./tools/Test-WordAddInPath.ps1` 7/7 PASS（A1 真实目录、B1 排除 Citavi bin、C1–C2 自动解析、D1 无效覆盖抛错、D2 有效覆盖原样返回、E1 空覆盖自动）；ISCC 6.7.3 编译 `Citavi6-zh.iss` Successful；独立复审确认 C1–C5 与 T4 均 FIXED。

**Journey log** — 1) 本机“探测正常”实为 `StartupSettings6.xml` 兜底，硬编码 `{pf}` 在 64 位 Office 上必失败。2) Citavi `bin` 也含 WordAddIn.dll，仅凭 DLL 判定会误判。3) Inno `NextButton.OnClick` 在 `/SILENT` 不执行，静默校验必须放 `PrepareToInstall`。4) 32 位 Setup 须用 `HKLM64` 才能读到 64 位 `Word\InstallRoot`。5) 中文 PS 脚本需保留 UTF-8 BOM 以兼容 Windows PowerShell 5.1。

## [S1] Problem

在部分 Windows 机器上，语言包安装器无法自动定位 Citavi Word 加载项目录（`…\ADDINS\Citavi Word AddIn`），表现为：

1. **路径框空白**：`Setup.exe`（Inno）的 `DetectWordBin()` 只在 32 位 `{pf}`（`Program Files (x86)`）下查找固定 Office 路径；64 位 Office 安装在 `C:\Program Files\Microsoft Office\…` 时硬编码全部落空。本机看似正常，是因为 `StartupSettings6.xml` 恰好记录了加载项目录；探测链本身并未命中。
2. **误填 Citavi bin**：勾选「安装到 Word 加载项」且探测失败时，`WordCheckClick` 会 `DetectCitaviBin()` 兜底，把 Word 路径填成 Citavi 的 `bin`（对 Word 无意义，且该目录也含 `SwissAcademic.Citavi.WordAddIn.dll`，进一步造成误判）。
3. **`StartupWordBin` 误判**：仅判断目录内是否有 `SwissAcademic.Citavi.WordAddIn.dll`，不排除 Citavi 自身 `bin`，可能把 Citavi 安装目录当作加载项目录。
4. **安装 UX 宽松**：路径框接受任意字符串（含 `Word.lnk` 等无效路径），要到「下一步」才校验；取消/勾选切换会清空或乱填，用户难以理解「留空=跳过」。
5. **四套安装器策略不一致**：`Install-Gui.ps1` / `Install-Toolkit.ps1` 已扫描双 Program Files 并递归找 DLL，`Install-LanguagePack.ps1` 只扫 Office16 固定路径，Inno 更弱；行为与文案不统一，问题只在主分发路径 `Setup.exe` 上暴露。

根因（已复现）：32 位 Setup.exe 的 `{pf}` 展开为 `Program Files (x86)`，而 64 位 Word/Citavi 加载项在 `Program Files`；注册表 `HKLM\SOFTWARE\Microsoft\Office\16.0\Word\InstallRoot`（64 位视图）可推导路径，但 32 位进程默认读不到。

## [S2] Design

### 目标行为

在常见 Office 布局下自动定位 Word 加载项目录；找不到则**留空**并允许取消勾选跳过，**绝不**回退到 Citavi bin 或其他无关路径。四套安装入口使用**同一探测契约**。

### 有效目录判定 `IsValidWordAddInDir(Dir)`

同时满足：

1. `Dir` 非空且为已存在目录；
2. 存在 `SwissAcademic.Citavi.WordAddIn.dll`；
3. **不存在** `Citavi.exe`（排除 Citavi `bin`）。

### 探测契约 `ResolveWordAddInDir()`

按优先级取第一个 `IsValidWordAddInDir` 的结果；全部失败则返回空：

| 序 | 来源 | 细则 |
|---|---|---|
| 1 | 显式覆盖 | 命令行 `/WORDBIN=` / `-WordAddInDir`；若指定但未通过判定则报错（不静默改写） |
| 2 | 注册表推导 | 读 64 位与 32 位视图下的 `SOFTWARE\Microsoft\Office\<ver>\Word\InstallRoot` 的 `Path`（ver ∈ 16.0/15.0/14.0），在该目录的 `ADDINS\Citavi Word AddIn` 与「Path 的上一级 + ADDINS\Citavi Word AddIn」中查找；并读 `SOFTWARE\Microsoft\Office\ClickToRun` 的 `PackageFolder`/`InstallPath` 下 `root\Office16\ADDINS\Citavi Word AddIn` |
| 3 | 约定路径 | 同时尝试 `{pf32}` 与 `{pf64}`（PowerShell 为 `ProgramFiles(x86)` 与 `ProgramFiles`/`ProgramW6432`）下 `Microsoft Office\Root\Office16\|15\|14\ADDINS\Citavi Word AddIn`，以及无 `Root` 的 `Microsoft Office\Office16\|…` 变体 |
| 4 | StartupSettings | 解析 `StartupSettings6.xml` 的 `ApplicationFolder`；必须通过 `IsValidWordAddInDir` |
| 5 | 文件系统 | 在 Program Files（双架构）及 `%LOCALAPPDATA%\Microsoft\Office` 下递归搜 `SwissAcademic.Citavi.WordAddIn.dll`（深度足够覆盖 ADDINS），用其所在目录并做第 3 条判定 |

Inno 注意：32 位安装器读注册表须用 `HKLM64` / `SetRegView(64)`，否则 64 位 `Word\InstallRoot` 不可见。

### 安装 UX 契约

1. **勾选「安装到 Word 加载项」**：
   - 若当前路径已 `IsValidWordAddInDir` → 保留；
   - 若为空 → 运行 `ResolveWordAddInDir()` 自动填充；
   - 仍为空 → **保持空**，提示可 Browse 或取消勾选跳过。禁止 `DetectCitaviBin()` 类回退。
2. **取消勾选** → 清空该路径框（= 跳过），不写入占位路径。
3. **路径变更/离开输入框（Inno：Next 前；PS：即时）**：
   - 通过判定 → 静默接受；
   - 否则提示「不是有效的 Word 加载项目录（需含 SwissAcademic.Citavi.WordAddIn.dll）」，勾选状态下阻止安装或要求清空/取消勾选。
4. **`重新检测路径`** → 对三个路径（Citavi / Word / 帮助）重跑各自解析器，不互相填充。
5. **`/WORDBIN=` 或 `-WordAddInDir` 显式指定**优先于自动探测；无效则明确失败。

### 统一实现边界

| 组件 | 改动 |
|---|---|
| `tools/installer/Citavi6-zh.iss` | 重写 `DetectWordBin`/`StartupWordBin`/`IsWordBin`；改 `WordCheckClick`、`RefreshPaths`、Next 校验 |
| `tools/Install-Toolkit.ps1` | `Resolve-WordAddInDir` 对齐契约（补注册表推导与约定路径变体；统一判定排除 Citavi.exe） |
| `tools/Install-Gui.ps1` | 同上，与 Toolkit 共享同一探测顺序与文案 |
| `tools/Install-LanguagePack.ps1` | `Find-WordAddInDir` 扩展到完整契约，不再只扫 Office16 两行 |

检测顺序、判定条件、失败文案以本节为准；允许各载体表达方式不同（Pascal vs PowerShell），不允许优先级或排除规则不一致。

### 错误与空态

- 自动探测失败 **不是** 安装错误：仅当用户勾选了 Word 项且路径无效/为空时才阻止继续（或引导取消勾选）。
- Citavi 主目录仍必填；Word 与快速帮助始终可选。

## [S3] Out of Scope

- 不改变实际安装内容（仍是向目标 `zh\` 复制附属程序集）。
- 不改「快速帮助」目录探测（`DetectHelpDir` / Custom Help）逻辑，除非共用的路径规范化函数被本改动触及。
- 不覆盖运行时联网帮助、元数据 Add-On、Citavi 本体。
- 不引入 npm/pip；不把 Office/Word COM 自动化作为探测依赖。
- 不处理「加载项未安装」时自动触发 Citavi 修复安装。

## Tasks

- [x] T1: Inno 判定与探测链 — acceptance: `IsWordBin` 含 Citavi.exe 排除；`DetectWordBin` 按 S2 序 1–5 含 `HKLM64` 与双 Program Files，缺一不可 (covers: S2)
- [x] T2: Inno 勾选/重检/校验 UX — acceptance: 勾选不再写入 Citavi bin；空态提示可跳过；Next 时无效路径有中文错误且不写入 `{win}` 占位后误装 (covers: S2)
- [x] T3: Toolkit/Gui/LanguagePack 对齐探测契约 — acceptance: 三套 PS 在「仅 64 位 Office 存在加载项、StartupSettings 无记录」的模拟环境下解析到同一真实目录；判定均排除 Citavi.exe (covers: S2; depends: T1)
- [x] T4: 探测回归验证脚本/用例 — acceptance: 可在本机跑通矩阵（命中 64 位 Office、空态不填 Citavi bin、`/WORDBIN=` 覆盖、无效覆盖报错）；记录命令与结果 (covers: S2; depends: T1, T3)
- [x] T5: 文档与文案同步 — acceptance: `tools/README.md`/README 安装说明与 S2 行为一致，不再暗示「自动失败可填 Citavi 路径」 (covers: S2; depends: T2)
