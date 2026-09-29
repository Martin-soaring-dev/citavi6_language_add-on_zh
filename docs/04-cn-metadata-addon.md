# 设计:中文文献元数据检索 Add-On

> 状态:**M1 调研完成(已反编译 6.20 + 实际编译验证)**;M2 起待实现。
> 目标读者:本项目维护者与贡献者。

## 1. 背景与目标

Citavi 原生的「按 DOI 检索参考文献」对中文期刊几乎必然失败。本项目要补上这块能力,使**中文用户开箱即用**。

**最终形态**:发布一个 **中文用户 Toolkit**,一个压缩包同时提供

1. **语言包**(`zh` 附属程序集,已实现);
2. **中文文献元数据 Add-On**(本文档主题)。

一站式解决「界面中文 + 中文文献查得到」。

## 2. 问题根因(已实测)

| 事实 | 实测证据 |
|---|---|
| 中文 DOI 由 **ISTIC(中信所)/万方数据** 注册 | `GET https://doi.org/api/handles/10.3969` → 注册机构 `10.SERV/ISTIC`,邮箱 `guoxf@wanfangdata.com.cn`;`10.3772` 的 DESC 为 `Wanfang data prefix` |
| 这类 DOI **只登记 URL,没有任何元数据** | `10.3969/j.issn.1673-5005.2026.03.005` → `responseCode:1`,values 里只有 `URL = https://d.wanfangdata.com.cn/periodical/sydxxb202603005` |
| Citavi 走 **CSL 内容协商**取元数据 | `Accept: application/vnd.citationstyles.csl+json` → 无字段可解析 |
| 万方详情页是 **Vue SPA**,接口用 **protobuf** | 165 KB HTML 中 `citation_*` 元标签为 0;脚本含 `app.js` / `api.js` / `chunk-protobuf.js` |
| 百度学术有反爬 | 检索返回 **403「百度安全验证」** |
| 万方/百度学术官方 API **只对机构开放** | 官网均写明面向图书馆/集成商 |

**结论**:`doi.org` 这条路在中文 DOI 上注定失败,必须换元数据源。

## 3. M1 调研结论:Citavi 的扩展机制(已实测)

> 来自对 `SwissAcademic.Citavi.dll`(Citavi 6.20)的反编译,以及 Add-On 的**实际编译验证**。

### 3.1 内置「按 DOI 检索」是硬编码的

`ReferenceIdentifierSupport.FetchDoiAsync()` 固定为三段式:

```
PubMed 在线导入源(SearchAttributeType.Doi) → CrossRefFetcher(内置) → DataCite Transformer
```

**结论**:放入自定义数据源**不会**自动改变内置 DOI 检索行为;要接中文源,必须由 **Add-On 提供自己的命令**驱动。

### 3.2 检索能力本身是 public、可复用 ✅

| 类型 | 命名空间 | 用途 |
|---|---|---|
| `IFetcher` | `SwissAcademic.Citavi.DataExchange` | `Transformer` / `DataExchangeProperty` / `Query` / `FetchAsync(ct)` |
| `IFetchResultSet` | 同上 | `Count` / `GetRecordAsync(index, ct)` → 返回**记录文本** |
| `Importer : ImportSession` | 同上 | `new Importer(fetcher, project){ DataExchangeProperty = query }` → `StartAsync()` / `GetReferenceAsync(0)` |
| `FetcherFactory` | 同上 | `new FetcherFactory().Create(transformer, query, null)` |
| `Transformer` | 同上 | `Id` / `Name` / `OnlineImportSettings` / `RecordLayout` / `Mapping` / `Load` / `Save` |
| `ReferenceIdentifierSupport` | 同上 | `FetchAsync(transformer, term, attribute, ct)` |
| `Reference.MergeReference(...)` | `SwissAcademic.Citavi` | 与官方 PubMed Add-On 同款合并方式 |

**关键收益**:只要 `IFetcher` 返回**标准记录文本**(RIS / BibTeX 等 Citavi 已支持的格式),
`Importer` + `Mapping` 会**自动完成「记录 → Reference 字段」映射** —— 无需自己写字段映射。

### 3.3 官方另有「声明式数据源」机制

- 本地 `.CitaviTX`(XML)映射文件放在
  `%APPDATA%\Swiss Academic Software\Citavi 6\Settings\Mappings\`,
  `DesktopTransformerManager.Initialize()` 会**自动扫描并加载**为在线导入源。
- `DesktopTransformerManager.Add(Transformer)` 为 **public**,Add-On 可在运行时注册数据源。
- `TransformerSettings.Code` 是**加密的 C# 代码**,Citavi 用 `CSharpCompiler.Compile()` **运行时编译**,
  实现自定义 `FetchAsync` / `GetRecord`。加密为 AES-256 + `PasswordDeriveBytes`
  (`CryptographyHelper`,密钥/盐硬编码在程序集内)→ 我们**可自行生成**。

> 该机制适合让数据源出现在 Citavi 的**在线检索**列表供手动选用,不适合替换内置 DOI 检索。

### 3.4 骨架可行性:已验证 ✅

用 VS 2022 的 Roslyn `csc` 引用 Citavi `bin` 下的
`Citavi.exe`、`SwissAcademic.dll`、`SwissAcademic.Citavi.dll`、`SwissAcademic.Controls.dll`、
`SwissAcademic.Resources.dll`、**`netstandard.dll`**、`System.ValueTuple.dll`,
已成功编译出继承 `CitaviAddOn<MainForm>`、挂载「文献条目」菜单、读取
`Reference.Title/Doi/Year/PageRange/PubMedId` 的 Add-On。

> ⚠️ 必须引用 Citavi `bin` 里的 `netstandard.dll`,否则报 `CS0012 System.ValueType 未定义`。

## 4. 数据源与方案

### 方案 B:DOI 结构解析 + 刊名表(轻量兜底)

中文 DOI 大量形如 `10.3969/j.issn.<ISSN>.<年>.<期>.<序号>`:

```
10.3969/j.issn.1003-0077.2026.08.009
       └── ISSN 1003-0077 ─┘ └年┘ └期┘ └序号┘
```

**可自动填**:期刊名(ISSN→刊名表)、年、期、DOI。**拿不到**:标题、作者。
**优点**:零网络、永不失效、实现量小。**缺点**:信息不完整。

### 方案 A:自定义 `IFetcher` + 渲染/HTTP(主力)

Add-On 实现 `IFetcher`,返回**标准记录文本**,交给 Citavi 的 `Importer` 解析映射。

- **获取方式**:优先 `HttpClient`(服务端渲染的**期刊官网**、OpenAlex、Handle API);SPA(万方/百度学术)再用 **WebView2** 渲染取文本;
- **目标页优先级**:DOI 的 Handle URL → 期刊官网(多为 SSR,如 `jcip.cipsc.org.cn`)→ 按标题检索。

**为什么可行**:Citavi 天然带 WebView2(`Microsoft.Web.WebView2.*`),且我们要做的只是"把页面内容变成 RIS/BibTeX"。

### 方案 C:OpenAlex / Crossref 兜底

中文覆盖不全(实测《中文信息学报》ISSN 1003-0077 有 1185 条,但部分 DOI 为空),匿名限流,建议申请免费 key。

### 方案 D(远期):机构 API

万方/百度学术对图书馆开放官方接口,可在设置中填凭据,作为最高质量来源。

### 组合策略

```
中文 DOI?
 ├─ 是 → ① Handle API 取 URL → 方案 A(HTTP → 必要时 WebView2)
 │        └─ 失败 → ③ 方案 C(按标题) → ④ 方案 B(兜底)
 └─ 否 → Citavi 原生 → 失败 → ③ → ④
```

## 5. 字段映射

由于采用 `Importer` + RIS/BibTeX,大部分映射由 Citavi 完成。需自行处理的仅:

| 来源 | Citavi | 说明 |
|---|---|---|
| 中文作者串 | `Person` 集合 | 中文姓名整体录入;先按 `;`/`,` 切分,保留原始串 |
| 页码 `57-68` / `99-107, 174` | `PageRange` | 需容错解析 |
| 语言 | `Language` | 中文文献设为 `zh` |
| 期刊 | `Periodical` | 已有则复用,无则创建 |

> `Title` / `Doi` / `Year` / `PageRange` / `PubMedId` / `ShortTitle` / `Isbn` 已在官方 Add-On 源码中确认。

## 6. UI / 交互设计

**入口**(与官方 PubMed 补全同级):

```csharp
mainForm.GetMainCommandbarManager()
    .GetReferenceEditorCommandbar(MainFormReferenceEditorCommandbarId.Menu)
    .GetCommandbarMenu(MainFormReferenceEditorCommandbarMenuId.References)
    .InsertCommandbarButton(4, ButtonKey, "中文文献元数据检索", image: Resources.addon);
```

| 命令 | 行为 |
|---|---|
| 检索当前条目 | 对 `mainForm.ActiveReference` 执行 |
| 批量检索选中条目 | 对 `GetFilteredReferences()` 执行,带进度与取消 |
| 仅按 DOI 解析刊名/年/期 | 方案 B,离线、瞬时 |
| 设置 | 数据源顺序、超时、是否覆盖已有字段、OpenAlex key |

**批量执行**:复用官方做法 —— `GenericProgressDialog.RunTask(...)` + `CancellationToken`,
结束后用 `ReferenceFilter` 把改动过的条目做成过滤器。
**预览对话框**:列出"字段 / 原值 / 新值",默认只填空字段。

## 7. 技术实现要点

| 主题 | 设计 |
|---|---|
| Add-On 骨架 | `CitaviAddOn<MainForm>`,重写 `OnHostingFormLoaded` / `OnBeforePerformingCommand` / `OnLocalizing` |
| 引用与编译 | 引用 Citavi `bin` 下 `Citavi.exe` + `SwissAcademic*.dll` + **`netstandard.dll`**;用 VS Roslyn `csc` 或 MSBuild |
| 抓取脚本 | 选择器不写死在 C# 里:内置默认脚本 + 支持用户目录覆盖,便于页面改版热修 |
| WebView2 | 必须在 STA 线程创建;离屏窗口 → `EnsureCoreWebView2Async()` → `Navigate()` → 等 `NavigationCompleted` + `readyState` |
| 网络 | 统一超时(默认 20s)、指数退避重试、批量限流(≥1s/条) |
| 缓存 | 以 DOI/标题为键,TTL 7 天 |
| 日志 | 写入 `%LOCALAPPDATA%\...\cn-metadata.log` |
| 可测试性 | DOI 解析/字段映射等纯逻辑与 WebView2 解耦,便于 CI 单测(不需 Citavi) |

## 8. 数据文件

```
data/
├─ issn-journal.tsv     # ISSN<TAB>刊名<TAB>别名(方案 B/D)
└─ cn-doi-prefixes.tsv  # 中文 DOI 前缀 → 注册机构/解析策略
```

支持"从远程更新",避免必须发新版 DLL。

## 9. 仓库与发布布局(Toolkit)

```
citavi6_language_add-on_ZH/
├─ translations/  docs/  tools/        # 语言包(现状)
├─ addon/                              # 新增:Add-On 源码
│  ├─ src/CnMetadataAddon/
│  ├─ data/issn-journal.tsv
│  ├─ build.ps1
│  └─ README.md
└─ .github/workflows/release.yml       # 改为打包 Toolkit
```

**发布产物(一个压缩包)**

```
citavi6-zh-toolkit-v0.1.zip
├─ 安装说明.txt
├─ language-pack/zh/*.resources.dll    → C:\Program Files (x86)\Citavi 6\bin\zh\
├─ addon/CnMetadataAddon/              → C:\Program Files (x86)\Citavi 6\AddOns\CnMetadataAddon\
│  ├─ CnMetadataAddon.dll
│  ├─ manifest.json
│  └─ addon.png
└─ data/issn-journal.tsv
```

`安装说明.txt` 分两步讲清「装语言包」与「装 Add-On」,两者**可独立安装**。

## 10. 风险与合规

| 风险 | 影响 | 缓解 |
|---|---|---|
| 抓取第三方站点 | 可能触及 ToS;页面改版即失效 | 只抓公开题录;限流;脚本热更新;提供纯离线模式(方案 B) |
| 反爬策略变化 | 批量失败 | WebView2 + 限流 + 退避;降级 C/B |
| 中文姓名解析 | 作者字段错乱 | 提供"保守模式"(不自动改作者) |
| 与原生 DOI 检索冲突 | 用户困惑 | 菜单文案区分;不改动原生行为 |
| Citavi 版本升级 | API 漂移 | `manifest.json` 声明 `citavi_min_version`;CI 构建校验 |

## 11. P0 待确认问题(M1 已解答大部分)

| # | 问题 | 状态 |
|---|---|---|
| 1 | `ReferenceIdentifierSupport` 是否可扩展(自定义数据源) | ✅ 可:实现 `IFetcher` + `Importer`,`Transform`/`.CitaviTX` 亦可注册 |
| 2 | `Reference` 字段属性名 | ✅ 已确认 `Title`/`Doi`/`Year`/`PageRange`/`PubMedId`/`ShortTitle`/`Isbn`;其余实现时核实 |
| 3 | Add-On 手动安装目录 | ✅ `C:\Program Files (x86)\Citavi 6\AddOns`(官方手册) |
| 4 | 能否编译出 Add-On | ✅ 已用 Roslyn `csc` 编译成功 |
| 5 | 万方/期刊官网的稳定抓取方式 | ⬜ 待实现时验证(优先 SSR 期刊官网) |
| 6 | `manifest.json` 的最小必填字段 | ⬜ 待实现时验证(参照官方示例) |

## 12. 里程碑与工作量(粗略)

| 阶段 | 内容 | 预估 |
|---|---|---|
| M1 | P0 调研 + 骨架 + 菜单命令 + 预览对话框(空实现) | ✅ 调研完成;骨架编译已验证 |
| M2 | 方案 B:DOI 结构解析 + ISSN 刊名表 + 离线填刊名/年/期 | 1~2 天 |
| M3 | 方案 C:OpenAlex/Crossref 按标题/DOI 回查 + RIS 输出 → `Importer` 映射 | 1~2 天 |
| M4 | 方案 A:HTTP/WebView2 抓取(优先 1~2 个 SSR 期刊官网) | 3~5 天 |
| M5 | 批量检索 + 进度/取消 + 缓存 + 日志 | 2 天 |
| M6 | Toolkit 打包与文档、CI、发布 | 1 天 |

## 13. 下一步

M1 已完成(调研 + 骨架可行性)。建议按 **M2 → M3 → M4** 推进:

- **M2** 不依赖任何外部站点,可立即产出可见效果(自动补齐刊名/年/期);
- **M3** 让英文/部分中文文献也能补全;
- **M4** 再攻克万方/期刊官网的抓取。
