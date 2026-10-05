# Citavi 6 中文语言包 (zh)

为 **Citavi 6**(Windows 桌面版,瑞士学术软件 / Lumivero)提供的**简体中文界面语言包**。

安装后在 Citavi 的「工具 → 语言 / Tools → Language」菜单中会出现 **中文**,选择即可切换为中文界面。

> 本项目不修改 Citavi 的任何原始文件,只向安装目录新增语言资源;卸载 = 删除新增目录。

> **当前版本:v0.102** — 已完成一轮术语统一与语境校对;仍有长尾条目待人工校对,发现措辞问题欢迎提交 PR。

---

## 项目构成(中文用户 Toolkit)

本项目定位为 **面向中文用户的一站式 Toolkit**,一个发布包含两部分,可**独立安装**:

| 组件 | 作用 | 状态 |
|---|---|---|
| **语言包** | Citavi 6 界面简体中文(本仓库主体) | ✅ v0.1 可用 |
| **Citavi 快速帮助(中文)** | 汉化右侧「快速帮助」面板(622 个主题,写入 `Documents\Citavi 6\Custom Help`;含「选择文献类型」按 35 种类型变化的帮助) | ✅ |
| **中文文献元数据 Add-On** | 解决中文期刊 DOI 查不到元数据的问题 | 📝 [设计稿](docs/04-cn-metadata-addon.md) |

> 中文期刊 DOI(ISTIC/万方注册)在 `doi.org` 上**没有元数据**,Citavi 原生「按 DOI 检索」必然失败。
> 设计稿分析了根因、数据源与三种实现方案(DOI 结构解析 / WebView2 渲染抓取 / OpenAlex 兜底)。

---

## 目录

- [效果 / 原理](#效果--原理)
- [支持与限制](#支持与限制)
- [安装](#安装)
- [目录结构](#目录结构)
- [开发与构建](#开发与构建)
- [参与翻译](#参与翻译)
- [免责声明](#免责声明)

---

## 效果 / 原理

Citavi 6 的界面文字使用标准 .NET **附属程序集(satellite assemblies)** 实现国际化。安装目录 `bin\` 下每一个语言子目录(`de`、`fr`、`es` …)就是一个语言包,里面是 `*.resources.dll`。

Citavi 在启动时**扫描 `bin\` 的子目录**来生成语言菜单:凡目录名匹配语言代码规则、且目录内存在 `SwissAcademic.Resources.resources.dll`,就视为一个已安装语言。因此只需新增一个 `zh\` 目录,中文就会自动出现在语言菜单中。

详细机制、反编译证据与全部技术约束见 **[docs/01-mechanism.md](docs/01-mechanism.md)**。

## 支持与限制

| 项目 | 说明 |
|---|---|
| 支持版本 | Citavi 6.x(基于 6.20 开发) |
| 目标语言 | 简体中文(`zh`,菜单显示为「中文」) |
| 覆盖范围 | 7 个程序集(含 Word 加载项)、52 个资源组、共 **11,612** 条字符串;外加 **622 条「快速帮助」**(Custom Help);未翻译的条目自动回退显示英文 |
| 不修改原程序 | ✅ 仅新增 `bin\zh\` 目录与 `文档\Citavi 6\Custom Help`(快速帮助) |
| 随 Citavi 升级 | 升级后新增的词条会显示英文,需运行同步脚本补译 |
| 动态/联网帮助 | 少数对话框(**按 ID 检索、查找馆藏位置、引文样式**等)运行时**直接联网**取帮助,官方服务无中文,语言包无法覆盖 → 这些保持英文(详见 [docs/05](docs/05-language-pack-backlog.md)) |

> 注:目录名不能使用 `zh-Hans`——Citavi 的语言目录名正则只接受 `xx` 或 `xx-XX` 形式,故本项目使用 `zh`。

## 安装

**一键安装(推荐)**:解压后双击 **`安装.vbs`**。启动时会**请求管理员权限(UAC)**(写入 Citavi / Word 加载项目录需要);它会自动检测 Citavi 6、Word 加载项与「快速帮助」目录、**预览计划**、必要时**弹窗提示关闭冲突进程(显示名称+PID)**,再以覆盖方式安装语言包与快速帮助,完成后弹窗。
> 只预览不执行:`pwsh ./Install-Toolkit.ps1 -WhatIf`;手动指定路径:`-CitaviBin` / `-WordAddInDir` / `-CustomHelpDir`。

**手动安装**

1. 下载 / 克隆本仓库。
2. 将 `dist/zh/` 整个目录复制到 Citavi 安装目录下的 `bin\` 内,例如:
   ```
   C:\Program Files (x86)\Citavi 6\bin\zh\
   ```
   (需要管理员权限)
   > **Word 加载项**:加载项从 Office 的 `ADDINS\Citavi Word AddIn` 目录运行,若要它也是中文,
   > 需把同一 `zh` 文件夹再复制到该目录下,例如
   > `C:\Program Files\Microsoft Office\Root\Office16\ADDINS\Citavi Word AddIn\zh\`;然后重启 Word。
3. 启动 Citavi → 工具 → 语言 → 选择「中文」。
4. 若未立即生效,重启 Citavi。

**脚本安装**

```powershell
# 复制 dist/zh/ 到 Citavi 的 bin 目录(通常需管理员权限的终端)
pwsh ./tools/Install-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"

# 卸载
pwsh ./tools/Install-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin" -Uninstall
```

**卸载**:删除 `bin\zh\` 目录,并在语言菜单切回其他语言即可。

## 目录结构

```
.
├─ README.md
├─ docs/
│  ├─ 01-mechanism.md           # 语言机制与反编译证据(核心文档)
│  ├─ 02-roadmap.md             # 实施计划与流水线设计
│  ├─ 03-translation-guide.md   # 翻译规范与术语表
│  └─ 04-cn-metadata-addon.md   # 【设计稿】中文文献元数据 Add-On
├─ addon/                       # 【规划】中文文献元数据 Add-On 源码
├─ tools/                       # 构建/提取/安装脚本(骨架,待实现)
│  ├─ Extract-Resources.ps1
│  ├─ Build-LanguagePack.ps1
│  └─ Install-LanguagePack.ps1
├─ translations/                # 翻译源文件(key → 中文),按资源组拆分
│  └─ README.md
├─ reference/                   # 从 Citavi 提取的原始资源(不入库)
└─ dist/                        # 构建产物 dist/zh/*.resources.dll(不入库)
```

## 开发与构建

流水线设计见 [docs/02-roadmap.md](docs/02-roadmap.md)。当前脚本均已可用:

```powershell
# 1. 提取英文源(需要 Citavi 6 安装目录)
pwsh ./tools/Extract-Resources.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"

# 2. 切分片 → 翻译 → 合并回填
pwsh ./tools/Prepare-TranslationShards.ps1 -ShardSize 250
#    (逐个翻译 reference/shards/shard-XXX.tsv → shard-XXX.zh.tsv)
pwsh ./tools/Merge-TranslationShards.ps1
pwsh ./tools/Test-Translations.ps1

# 3. 构建出 dist/zh/ 下的 7 个附属程序集
pwsh ./tools/Build-LanguagePack.ps1

# 4. 不启动 Citavi 验证语言包可被正确解析
pwsh ./tools/Test-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"

# 5. 安装 / 打包分发
pwsh ./tools/Install-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"
pwsh ./tools/Package-Release.ps1 -Version 0.1
```

所需环境:Windows + .NET Framework 4.x(自带 `csc.exe`);无需 Visual Studio。

## 自动构建与发布

仓库自带 GitHub Actions(Windows runner,无需 Citavi):

| 工作流 | 触发 | 行为 |
|---|---|---|
| `validate` | push 到 `main` / PR / 手动 | 校验译文 → 构建 → 打包 zip,作为 **Artifact** 可下载 |
| `release` | **在 GitHub 上发布 Release** / 推送 `v*` 标签 / 手动 | 校验 → 构建 → 打包 → **把 zip 附到该 Release** |

发布方式二选一:

**A. 在 GitHub 网页上发布**(推荐)

`Releases → Draft a new release` → 填 tag(如 `v0.1`)→ `Publish release`。
CI 会自动构建并把 `citavi6-zh-v0.1.zip` 附加到这个 Release 上(不会覆盖你写的发布说明)。

**B. 命令行**

```bash
git tag v0.1 && git push origin v0.1        # CI 自动创建 Release 并附 zip
gh release create v0.1                       # 先建空 Release,CI 之后自动补上 zip
```

> 注意:workflow 文件必须存在于**默认分支**,`release` 事件才会触发。

## 参与翻译

翻译文本位于 `translations/`,格式与规范见 [docs/03-translation-guide.md](docs/03-translation-guide.md) 与 [translations/README.md](translations/README.md)。

## 免责声明

- Citavi 是 Swiss Academic Software / Lumivero 的注册商标与商业软件。本项目为社区汉化,与官方无关联。
- 本项目**不包含** Citavi 的任何原始程序集或二进制文件,仅包含社区翻译的字符串资源。
- 使用本语言包的风险由使用者自行承担;建议在切换语言前备份项目数据。

## 相关

- 官方组织:https://github.com/LUMIVERO
- Citavi 6 Add-Ons 源码(了解扩展模型):https://github.com/LUMIVERO/C6-Add-Ons-and-Online-Sources
