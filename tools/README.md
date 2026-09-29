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
| `Test-Translations.ps1` | 校验 TSV 格式与占位符一致性 |
| `Test-LanguagePack.ps1` | 不启动 Citavi,验证语言包能被 .NET 正确解析 |
| `Install-LanguagePack.ps1` | 把 `dist/zh/` 复制到 Citavi `bin\`(可卸载) |
| `Package-Release.ps1` | 生成可分发 zip |

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

## 环境要求

- Windows
- .NET Framework 4.x(`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`)
- PowerShell 7(`pwsh`)
- 提取需要本机安装 Citavi 6
- `Setup-TranslateMcp.ps1` / `mcp_translate.py` 需要 Python 3

## 说明

- 分片文件 `reference/shards/` 与缓存 `reference/mt-cache.json` 都不入库。
- 模型翻译产物仍是**初稿**,建议持续人工校对。

技术细节见 [../docs/01-mechanism.md](../docs/01-mechanism.md) 与 [../docs/02-roadmap.md](../docs/02-roadmap.md)。
