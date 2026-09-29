# 设计:中文文献元数据检索 Add-On

> 状态:**设计稿(未实现)**
> 目标读者:本项目维护者与贡献者。

## 1. 背景与目标

Citavi 原生的「按 DOI 检索参考文献」(`ReferenceIdentifierDownloadOptionsDialog_Doi`)对中文期刊几乎必然失败。本项目要补上这块能力,使**中文用户开箱即用**。

**最终形态**:发布一个 **中文用户 Toolkit**,一个压缩包里同时提供

1. **语言包**(`zh` 附属程序集,已实现);
2. **中文文献元数据 Add-On**(本设计文档的主题)。

一站式解决「界面中文 + 中文文献能查得到」。

## 2. 问题根因(已实测)

| 事实 | 实测证据 |
|---|---|
| 中文 DOI 由 **ISTIC(中信所)/万方数据** 注册 | `GET https://doi.org/api/handles/10.3969` → 注册机构 `10.SERV/ISTIC`,联系邮箱 `guoxf@wanfangdata.com.cn`;`10.3772` 的 DESC 为 `Wanfang data prefix` |
| 这类 DOI **只登记 URL,没有任何元数据** | `GET https://doi.org/api/handles/10.3969/j.issn.1673-5005.2026.03.005` → `responseCode:1`,但 values 里只有一个 `URL = https://d.wanfangdata.com.cn/periodical/sydxxb202603005` |
| Citavi 走 **CSL 内容协商**取元数据 | `https://doi.org/<doi>` + `Accept: application/vnd.citationstyles.csl+json` → 无字段可解析 |
| 万方详情页是 **Vue SPA**,接口用 **protobuf** | 165 KB HTML 中 `citation_*` 元标签为 0;脚本含 `app.js` / `api.js` / **`chunk-protobuf.js`** |
| 百度学术有反爬 | 检索请求返回 **403「百度安全验证」** |
| 万方/百度学术的官方 API **只对机构开放** | 官网均写明面向图书馆/集成商 |

**结论**:`doi.org` 这条路在中文 DOI 上注定失败,必须换元数据源;而主要中文源都没有免费公开 API,需要「渲染抓取 + 兜底解析」的组合。

## 3. 关键发现:Citavi 自带标识符检索框架

`UpdateBibliographicDataFromPubMedSearch` 这个官方 Add-On 里使用了:

```csharp
using SwissAcademic.Citavi.DataExchange;
...
var identifierSupport = new ReferenceIdentifierSupport(project);
var lookedUpReference = await identifierSupport.FindReferenceAsync(
        project, new ReferenceIdentifier() { Type = ReferenceIdentifierType.XXX, ... });
```

也就是说 Citavi 内部把「DOI / PMID / ISBN 检索」抽象成了
`ReferenceIdentifier(Type, Value)` → `ReferenceIdentifierSupport.FindReferenceAsync(...)` → `Reference`。

**这是最高价值的切入点(P0 待查)**:

- 若 `ReferenceIdentifierSupport` 支持注册**自定义解析器/RAG 源**,我们就能像加语言包一样"顺着官方机制"扩展,而不是另起一套;
- 若不可扩展,退而求其次:Add-On 自己实现检索,但**仍复用** `ReferenceIdentifier` / `ReferenceIdentifierSupport` 的类型约定,以便与 Citavi 的导入/合并逻辑兼容。

> 待查清单见 §11。

## 4. 方案设计

### 方案 B:DOI 结构解析 + 刊名表(轻量兜底,先行)

中文 DOI 大量采用可解析的结构:`10.3969/j.issn.<ISSN>.<年>.<期>.<序号>`。

```
10.3969/j.issn.1003-0077.2026.08.009
       └── ISSN 1003-0077 ─┘ └年┘ └期┘ └序号┘
```

**可自动填**:期刊名(ISSN→刊名表)、年、期、DOI;序号可用于**排序/核对**。
**拿不到**:标题、作者。

**解析规则(按优先级匹配多条正则)**

| 模式 | 示例 | 可抽取 |
|---|---|---|
| `j.issn.<ISSN>.<YYYY>.<NN>.<S>` | `10.3969/j.issn.1003-0077.2026.08.009` | ISSN、年、期、序号 |
| `j.<刊名缩写>.<YY><NN><S>` | `10.13245/j.hust.200101` | 仅年份(不完全可靠) |
| `j.issn.<ISSN>.<YYYY>` | `10.11817/j.issn.1672-7347.2020.190218` | ISSN、年 |

**刊名表**:`data/issn-journal.tsv`(`ISSN<TAB>刊名<TAB>别名`),随仓库维护,支持后续从公开数据批量更新。数据量可控(常用中文期刊数千种)。

**优点**:零网络依赖、永不失效、实现量小(1~2 天)。
**缺点**:信息不完整,只解决"刊名/年/期"。

### 方案 A:WebView2 渲染抓取(主力)

Citavi 自带 WebView2(其 `bin` 目录含 `Microsoft.Web.WebView2.Core.dll` / `.WinForms.dll` / `.Wpf.dll`),Add-On 可以直接托管一个隐藏的 WebView2。

**流程**

```
选中条目
  ├─ 有 DOI ──► 判断是否中文 DOI(前缀 10.3969 / 10.3772 / 10.11817 …)
  │              ├─ 是 ──► doi.org/api/handles/<doi> 取真实 URL(多为万方/期刊官网)
  │              └─ 否 ──► 走 Citavi 原生(CSL / CrossRef)
  └─ 无 DOI ──► 用「标题(+作者)」在数据源检索
        │
        ▼
 隐藏 WebView2 导航到目标页 → 等待渲染完成 → ExecuteScriptAsync 注入 JS 抓 DOM
        │
        ▼
 字段映射 → 预览对话框(可勾选要覆盖的字段)→ 写入 Reference
```

**目标页优先级**

1. DOI 的 Handle URL 指向的页面(万方详情页 / 期刊官网);
2. **期刊官网**通常比万方更好抓(很多是服务端渲染的,如 `jcip.cipsc.org.cn`、`zkjournal.upc.edu.cn`);
3. 万方检索页(按标题)。

**为什么用 WebView2 而不是 HTTP 抓取**

- 目标是 SPA,必须执行 JS;
- 天然带完整 UA / Cookie / TLS 指纹,**比 HTTP 抓取更不容易被反爬拦截**。

**风险**:页面改版即失效 → 需要把"抓取规则"做成**可配置/可热更新的脚本**,而不是硬编码在 DLL 里(见 §7)。

### 方案 C:OpenAlex / Crossref 兜底

- `https://api.openalex.org/works?search=<标题>` 或 `filter=doi:<doi>`;
- 免费,但匿名有速率限制(实测 429),建议申请免费 API key;
- 中文刊覆盖不全(实测《中文信息学报》ISSN 1003-0077 有 1185 条记录,但部分条目 DOI 为空);
- 作为 A 失败后的第二来源。

### 方案 D(远期):机构 API

万方/百度学术对图书馆开放官方接口。若用户所在机构有权限,可在设置里填入凭据,作为最高质量来源。

### 组合策略(推荐)

```
中文 DOI?
 ├─ 是 → ① Handle API 取 URL → WebView2 抓取(方案 A)
 │        └─ 失败 → ③ OpenAlex 按标题(方案 C) → ④ DOI 结构解析兜底(方案 B)
 └─ 否 → Citavi 原生 → 失败 → ③ → ④
```

## 5. 字段映射

| 来源字段 | Citavi `Reference` | 说明 |
|---|---|---|
| 标题 | `Title` | 中文标题;若有英文副标题可放 `TitleSupplement` |
| 作者 | `Authors`(`Person` 集合) | 中文姓名按"姓名"整体录入;需处理逗号/分号分隔 |
| 期刊 | `Periodical` | 通过 ISSN 匹配/创建 `Periodical` |
| 年 | `Year` | int |
| 卷 / 期 | `Volume` / `Issue` | |
| 页码 | `PageRange` | 形如 `57-68`,也需处理 `99-107, 174` |
| DOI | `Doi` | |
| 摘要 | `Abstract` | 可选(默认不覆盖已有内容) |
| 关键词 | `Keywords` | 可选 |
| 语言 | `Language` | 中文文献设为 `zh` |

> 属性名以实际 Citavi 6.20 API 为准(`PageRange` / `Doi` / `PubMedId` / `ShortTitle` / `Isbn` 已在官方 Add-On 源码中确认;其余待核实)。

## 6. UI / 交互设计

**入口**(挂在「文献条目」菜单,与官方 PubMed 补全 Add-On 的位置一致):

```csharp
mainForm.GetMainCommandbarManager()
    .GetReferenceEditorCommandbar(MainFormReferenceEditorCommandbarId.Menu)
    .GetCommandbarMenu(MainFormReferenceEditorCommandbarMenuId.References)
    .InsertCommandbarButton(4, ButtonKey, "中文文献元数据检索", image: Resources.addon);
```

**命令**

| 命令 | 行为 |
|---|---|
| 检索当前条目 | 对 `mainForm.ActiveReference` 执行 |
| 批量检索选中条目 | 对 `GetFilteredReferences()` 执行,带进度与取消 |
| 仅按 DOI 解析刊名/年/期 | 方案 B,离线、瞬时 |
| 设置 | 数据源顺序、抓取脚本、超时、是否覆盖已有字段、OpenAlex key |

**批量执行**:复用官方做法 —— `GenericProgressDialog.RunTask(...)` + `CancellationToken`,结束后用 `ReferenceFilter` 把改动过的条目做成过滤器,方便复查。

**预览对话框**:列出"字段 / 原值 / 新值",默认只填空字段,用户可勾选覆盖。

## 7. 技术实现要点

| 主题 | 设计 |
|---|---|
| Add-On 骨架 | 参照 `LUMIVERO/C6-Add-Ons-and-Online-Sources`:`CitaviAddOn<MainForm>`,重写 `OnHostingFormLoaded` / `OnBeforePerformingCommand` / `OnLocalizing` |
| 目标框架 | .NET Framework 4.6.1;引用 Citavi `bin` 下的 `Citavi.exe` / `SwissAcademic*.dll`(`Private=False`) |
| 打包 | `manifest.json`(含 `Id`、`EntryPoint`、`Icon`、`citavi_min_version`、`name_localized` 含 `zh`)+ `addon.png` + DLL |
| 抓取脚本 | **不要把选择器写死在 C# 里**:内置一份默认 JS 脚本(随版本更新),并允许从用户目录加载覆盖版,便于页面改版后热修 |
| WebView2 线程 | 必须在 STA 线程创建;使用离屏窗口(不显示),`EnsureCoreWebView2Async()` → `Navigate()` → 等 `NavigationCompleted` + 轮询 `document.readyState` |
| 网络 | 统一超时(默认 20s)、失败重试(指数退避)、限流(批量时每条间隔 ≥ 1s,避免触发反爬) |
| 缓存 | 以 DOI/标题为键的本地缓存(默认 TTL 7 天),减少重复请求 |
| 失败可观测 | 记录日志到 `%LOCALAPPDATA%\...\cn-metadata.log`,便于用户反馈 |
| 可测试性 | 把"解析/映射/DOI 解析"等纯逻辑与 WebView2 解耦,便于单元测试(CI 里跑,不需要 Citavi) |

## 8. 数据文件

```
data/
├─ issn-journal.tsv     # ISSN<TAB>刊名<TAB>别名(用于方案 B/D)
└─ cn-doi-prefixes.tsv  # 中文 DOI 前缀 → 注册机构/解析策略
```

两条数据都应支持"从远程更新"(可选功能),避免必须发新版 DLL。

## 9. 仓库与发布布局(Toolkit)

```
citavi6_language_add-on_ZH/            ← 现仓库(语言包)
├─ translations/  tools/  docs/        # 现状不变
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
├─ language-pack/zh/*.resources.dll    → 复制到  C:\Program Files (x86)\Citavi 6\bin\zh\
├─ addon/CnMetadataAddon/              → 复制到  C:\Program Files (x86)\Citavi 6\AddOns\CnMetadataAddon\
│  ├─ CnMetadataAddon.dll
│  ├─ manifest.json
│  └─ addon.png
└─ data/issn-journal.tsv
```

`安装说明.txt` 分两步讲清「装语言包」与「装 Add-On」,并说明**两者可独立安装**。

> 现有 `Package-Release.ps1` 扩展为打包 Toolkit;`release.yml` 逻辑不变(仍跟随 tag)。

## 10. 风险与合规

| 风险 | 影响 | 缓解 |
|---|---|---|
| 抓取第三方站点(万方/期刊官网) | 可能触及 ToS;页面改版即失效 | 只抓公开可见的题录信息;限流;脚本热更新;提供"仅离线模式(方案 B)" |
| 反爬策略变化 | 批量检索失败 | WebView2 + 限流 + 退避;失败降级到 C/B |
| 中文姓名解析 | 作者字段错乱 | 先按 `;`/`,` 切分,保留原始串;提供"保守模式"(不自动改作者) |
| 与 Citavi 原生 DOI 检索冲突 | 用户困惑 | 菜单文案区分「中文文献元数据检索」;不改动原生行为 |
| Citavi 版本升级 | API 漂移 | `manifest.json` 声明 `citavi_min_version`;CI 构建校验 |

## 11. 待确认问题(P0)

1. **`ReferenceIdentifierSupport` 是否可扩展?**
   能否注册自定义 `ReferenceIdentifierType` / 自定义解析器 → 决定方案是"接入官方机制"还是"自建"。
   核实方式:反编译 `SwissAcademic.Citavi.dll`(本项目已有 ILSpy 流程)查看该类的公开成员与内部查找逻辑。
2. `Reference` 各字段的**准确属性名与类型**(`Title` / `Authors` / `Periodical` / `Volume` / `Issue` / `PageRange` / `Language`)。
3. 万方/期刊官网页面的**稳定选择器**;哪些中文期刊官网是服务端渲染(优先抓取对象)。
4. Add-On 的手动安装目录是否为 `C:\Program Files (x86)\Citavi 6\AddOns\<名称>\`(需实测)。
5. WebView2 在 Citavi 进程内初始化是否受限(运行时是否随 Citavi 安装)。

## 12. 里程碑与工作量(粗略)

| 阶段 | 内容 | 预估 |
|---|---|---|
| M1 | 完成 §11 的 P0 调研;搭 Add-On 骨架 + 菜单命令 + 预览对话框(空实现) | 1~2 天 |
| M2 | 方案 B:DOI 结构解析 + ISSN 刊名表 + 离线填 刊名/年/期 | 1~2 天 |
| M3 | 方案 C:OpenAlex/Crossref 按标题/DOI 回查与字段映射 | 1~2 天 |
| M4 | 方案 A:WebView2 渲染抓取(1~2 个数据源优先) | 3~5 天 |
| M5 | 批量检索 + 进度/取消 + 缓存 + 日志 | 2 天 |
| M6 | Toolkit 打包与文档、CI、发布 | 1 天 |

## 13. 立即可做的第一步

不依赖任何调研就能落地、且立刻有价值的是 **M2(方案 B)**:
把中文 DOI 里的 **ISSN / 年 / 期** 解析出来,配合刊名表自动补齐刊名。

要不要先做这一步?还是先做 M1 的 P0 调研(`ReferenceIdentifierSupport` 可扩展性)?
