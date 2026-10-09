# tools/

构建语言包的 PowerShell / Python 脚本。

| 脚本 | 作用 |
|---|---|
| `Extract-Resources.ps1` | 从 Citavi 安装目录提取英文字典 → `translations/*.tsv` |
| `Prepare-TranslationShards.ps1` | 把待翻译词条切成分片(`reference/shards/`)交给模型/译员 |
| `Merge-TranslationShards.ps1` | 合并分片译文并回填 `translations/*.tsv` |
| `Translate-Draft.ps1` | (备用)用免费 Google 接口机翻填充第 3 列 |
| `mcp_translate.py` | (备用)通过 MCP `translate-mcp-server` 批量翻译 |
| `Setup-TranslateMcp.ps1` | 安装/启动本地 `translate-mcp-server`(含两处必要补丁) |
| `Build-LanguagePack.ps1` | `translations/*.tsv` → `.resources` → `csc` 编译 → `dist/zh/` |
| `Test-Translations.ps1` | 校验 TSV 格式、占位符、SmartFormat 分支、HTML 标签、RTF/转义(CI 用 `-Strict`) |
| `Test-LanguagePack.ps1` | 不启动 Citavi,验证语言包能被 .NET 正确解析 |
| `Install-LanguagePack.ps1` | 把 `dist/zh/` 复制到 Citavi `bin\`(可卸载) |
| `Install-Gui.ps1` | WinForms 图形安装器;读取 `assets\setup.ico` + `assets\logo-symbol.png` 作窗体图标与头部徽标 |
| `Package-Release.ps1` | 生成可分发 zip(含 `zh`、快速帮助、安装脚本与 `assets\` 品牌位图) |
| `Build-BrandAssets.ps1` | 品牌 SVG → 安装包位图(`docs/brand/simple/export/win/`) |
| `Build-Installer.ps1` | 用 Inno Setup 打单文件 `Setup.exe`(编译前校验品牌位图存在) |

## 主流程(模型翻译)

```powershell
# 0) 仅首次:从 Citavi 安装目录提取英文源
pwsh ./tools/Extract-Resources.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"

# 1) 切分片(默认每片 250 条,输出 reference/shards/shard-XXX.tsv)
pwsh ./tools/Prepare-TranslationShards.ps1 -ShardSize 250

# 2) 翻译:每个 shard-XXX.tsv 交给一个译员/子代理,
#    产出同名的 shard-XXX.zh.tsv,格式 "<id>\t<中文>"

# 3) 合并 + 回填
pwsh ./tools/Merge-TranslationShards.ps1

# 4) 校验 / 构建 / 验证 / 打包
pwsh ./tools/Test-Translations.ps1
pwsh ./tools/Build-LanguagePack.ps1
pwsh ./tools/Test-LanguagePack.ps1 -CitaviBin "C:\Program Files (x86)\Citavi 6\bin"
pwsh ./tools/Package-Release.ps1 -Version 0.1
```

分片流程可反复执行:合并后再次 `Prepare-TranslationShards.ps1` 只会切出仍未翻译的词条。

## 备用机翻通道

免费 Google 接口在批量下会被限流(429/403),因此不建议作为主通道。若要用:

```powershell
pwsh ./tools/Translate-Draft.ps1              # 直接调用免费 Google 接口
pwsh ./tools/Setup-TranslateMcp.ps1 -Start    # 启动 translate-mcp-server(需先安装)
python ./tools/mcp_translate.py --workers 4   # 经 MCP 批量翻译
```

## 品牌位图资产(安装程序用)

安装程序不能直接吃 SVG,所以 `docs/brand/simple/export/win/` 下有 4 份**提交入库**的位图:

```powershell
pwsh ./tools/Build-BrandAssets.ps1                 # 自动探测 Chrome / Edge / ms-playwright Chromium
pwsh ./tools/Build-BrandAssets.ps1 -Renderer edge   # 手动指定
```

产物:`setup.ico`(Setup.exe 与卸载项图标)、`wizard-image.png`(656×1256,Inno 固定 164:314)、
`wizard-small.png`(318×318 正方形)、`logo-symbol.png`(456×295,图形安装器头部)。
脚本用 headless Chromium 截图 SVG,再用 System.Drawing 缩放并组装 ICO,不引入 npm/pip 依赖;
中间页面写到 `build/brand/`(不入库)。

改过 `docs/brand/simple/svg/` 就要重跑并把位图一起提交 —— CI 只装 Inno Setup,没有光栅器。
`Build-Installer.ps1` 会在编译前检查这三份安装包资产是否存在,缺失直接报错。

## 环境要求

- Windows
- .NET Framework 4.x(`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`)
- PowerShell 7(`pwsh`)
- 提取需要本机安装 Citavi 6
- `Setup-TranslateMcp.ps1` / `mcp_translate.py` 需要 Python 3
- `Build-Installer.ps1` 需要 [Inno Setup](https://jrsoftware.org/isinfo.php)(`winget install JRSoftware.InnoSetup`)
- `Build-BrandAssets.ps1` 需要本机任一 headless Chromium(Chrome / Edge / `ms-playwright` 的 chromium)

## 说明

- 分片文件 `reference/shards/` 与缓存 `reference/mt-cache.json` 都不入库。
- 模型翻译产物仍是**初稿**,建议持续人工校对。

技术细节见 [../docs/01-mechanism.md](../docs/01-mechanism.md) 与 [../docs/02-roadmap.md](../docs/02-roadmap.md)。
