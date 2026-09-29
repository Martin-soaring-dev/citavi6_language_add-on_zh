# Citavi 6 中文语言包 (zh)

为 **Citavi 6**(Windows 桌面版,瑞士学术软件 / Lumivero)提供的**简体中文界面语言包**。

安装后在 Citavi 的「工具 → 语言 / Tools → Language」菜单中会出现 **中文**,选择即可切换为中文界面。

> 本项目不修改 Citavi 的任何原始文件,只向安装目录新增语言资源;卸载 = 删除新增目录。

> **当前版本:v0.1(机翻初稿)** — 全部词条已由机翻填充,尚待人工校对;发现措辞问题欢迎提交 PR。

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
| 覆盖范围 | 6 个程序集、50 个资源组、共 **11,593** 条字符串;未翻译的条目自动回退显示英文 |
| 不修改原程序 | ✅ 仅新增 `bin\zh\` 目录 |
| 随 Citavi 升级 | 升级后新增的词条会显示英文,需运行同步脚本补译 |

> 注:目录名不能使用 `zh-Hans`——Citavi 的语言目录名正则只接受 `xx` 或 `xx-XX` 形式,故本项目使用 `zh`。

## 安装

**手动安装**

1. 下载 / 克隆本仓库。
2. 将 `dist/zh/` 整个目录复制到 Citavi 安装目录下的 `bin\` 内,例如:
   ```
   C:\Program Files (x86)\Citavi 6\bin\zh\
   ```
   (需要管理员权限)
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
│  └─ 03-translation-guide.md   # 翻译规范与术语表
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

# 3. 构建出 dist/zh/ 下的 6 个附属程序集
pwsh ./tools/Build-LanguagePack.ps1

# 4. 不启动 Citavi 验证语言包可被正确解析
pwsh ./tools/Test-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"

# 5. 安装 / 打包分发
pwsh ./tools/Install-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"
pwsh ./tools/Package-Release.ps1 -Version 0.1
```

所需环境:Windows + .NET Framework 4.x(自带 `csc.exe`);无需 Visual Studio。

## 参与翻译

翻译文本位于 `translations/`,格式与规范见 [docs/03-translation-guide.md](docs/03-translation-guide.md) 与 [translations/README.md](translations/README.md)。

## 免责声明

- Citavi 是 Swiss Academic Software / Lumivero 的注册商标与商业软件。本项目为社区汉化,与官方无关联。
- 本项目**不包含** Citavi 的任何原始程序集或二进制文件,仅包含社区翻译的字符串资源。
- 使用本语言包的风险由使用者自行承担;建议在切换语言前备份项目数据。

## 相关

- 官方组织:https://github.com/LUMIVERO
- Citavi 6 Add-Ons 源码(了解扩展模型):https://github.com/LUMIVERO/C6-Add-Ons-and-Online-Sources
