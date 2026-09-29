# 翻译规范与术语表

面向 `translations/` 下译文的约定。目标:简体中文,风格与主流桌面软件一致。

## 文件格式

每行一条,使用 **制表符(Tab)** 分隔,共 3 列,文件编码 **UTF-8(无 BOM)**:

```
key<TAB>English<TAB>中文
```

- 第 1 列 `key`:资源键,**不得修改**。
- 第 2 列 `English`:英文原文(由提取脚本生成),**只读**,用于对照与机翻。
- 第 3 列 `中文`:译文。留空表示未翻译,构建时自动回退英文。

示例:

```
SearchForm_extendedSearchStartButton	Search	搜索
noButton	No	否
```

### 转义规则

为了避免换行破坏每行一条的格式,原文与译文中的特殊字符按如下转义(由脚本自动处理,手工编辑时请注意):

| 字符 | 写法 |
|---|---|
| 反斜杠 `\` | `\\` |
| 制表符 | `\t` |
| 回车 CR | `\r` |
| 换行 LF | `\n` |

例如原文:

```
The selected project ... synchronized by {1}.\r\n\r\nDo you want to select this folder anyway?
```

译文写作一行:

```
...由 {1} 同步的文件夹。\r\n\r\n是否仍要选择此文件夹?
```

### 文件位置与命名

```
translations/<程序集名>/<资源基名>.tsv
```

- `<程序集名>`:`Citavi`、`SwissAcademic`、`SwissAcademic.Citavi`、`SwissAcademic.Controls`、`SwissAcademic.Resources`、`SwissAcademic.WordProcessing`。
- `<资源基名>`:如 `SwissAcademic.Resources.FormTexts`,文件名即 `SwissAcademic.Resources.FormTexts.tsv`。
- 请**勿**重命名文件或改动前两列;新增语言由脚本处理。

## 通用规则

1. **占位符必须原样保留**:`{0}`、`{1}`、`{2}` … 数量与顺序不得改变。
   例:`Cannot open "{0}"` → `无法打开「{0}」`
2. **HTML 标签保留**:`<br/>`、`<b>`、`<span style="...">` 等结构保留,只翻译文本。
3. **快捷键提示**:`&File` 中的 `&` 表示菜单助记符,中文一般去掉 `&`(如 `&File` → `文件`);
   若保留助记符,只能用字母。
4. **标点**:中文用全角「」,句子末尾可用「。」;菜单项、按钮**不加**句号。
5. **省略号**:`...` 保留为 `…` 或 `...` 均可,遵循 UI 习惯统一。
6. **专有名词**:
   - `Citavi` 不翻译。
   - `Word`、`Excel`、`PDF`、`RIS`、`BibTeX`、`DOI`、`ISBN`、`ISSN` 等保持原文。
   - `Add-On` → `加载项`;`Macro` → `宏`;`Picker` → `浏览器插件`。
7. **长度控制**:按钮、标签、列标题尽量精炼,避免超长导致截断。
8. **不要**翻译纯技术标识、快捷键名(如 `CtrlShiftK`)、文件名、URL。

## 术语表(逐步完善)

| 英文 | 中文 |
|---|---|
| Reference | 参考文献 / 条目(视语境) |
| Knowledge item | 知识项 |
| Quotation | 摘录 |
| Category | 分类 |
| Keyword | 关键词 |
| Task | 任务 |
| Citation | 引用 |
| Citation style | 引用样式 |
| Bibliography | 参考文献目录 |
| Project | 项目 |
| Attachment | 附件 |
| Picker | 浏览器插件 |
| Add-On | 加载项 |
| Import / Export | 导入 / 导出 |
| Filter | 筛选 |
| Search | 搜索 |
| Location (online) | 资源库 |
| Field | 字段 |
| Person | 作者(视语境) |
| Institution | 机构 |
| Periodical | 期刊 |
| Cloud project | 云端项目 |
| Backup | 备份 |
| Shortcut | 快捷键 |

> 术语一旦确定,后续机翻与校对统一遵循;新增术语请追加到本表。

## 翻译流程

主流程是"分片 + 译员/模型翻译":

1. `tools/Prepare-TranslationShards.ps1` 把待翻译词条切成分片:
   `reference/shards/shard-XXX.tsv`,每行 `<id>\t<原文>`(id 为数字,原文单行转义)。
2. 每个分片交给一位译员(或一个子代理),产出 `reference/shards/shard-XXX.zh.tsv`,
   每行 `<id>\t<中文>`。
   - 用数字 id 作键,译员**不需要**抄写英文原文,避免抄错;
   - 必须保留全部 id 与顺序;
   - 遵守上面的转义规则,输出不得含真实换行/Tab。
3. `tools/Merge-TranslationShards.ps1` 校验 `{n}` 占位符后合并,并回填 `translations/`。
4. 未完成的分片可反复重跑;合并后再次 `Prepare-TranslationShards.ps1` 只会切出仍未翻译的词条。

### 跳过项与 SmartFormat

- 含 `|` **且不含** `{n:...}` 的词条(多语言占位符词表、文件过滤器等内部数据)默认**不翻译**,
  否则会改变 Citavi 的匹配行为。
- 但 .NET **SmartFormat 单复数条件**属于界面文本,**必须翻译**,并完整保留结构:

  | 原文 | 译文 |
  |---|---|
  | `{0:1 reference\|{0} references} total` | `{0:1 条参考文献\|{0} 条参考文献} 总计` |
  | `The {0:selected file\|{0} selected files}` | `已选 {0:文件\|{0} 个文件}` |

  要求:`{n:`、中间的 `|`、结尾的 `}` 位置不变;两个分支都译;分支内的 `{0}`/`{1}` 原样保留。
  中文无单复数,两分支译成相同说法也可以,但结构必须都在。

### 备用通道

免费 Google 接口(`Translate-Draft.ps1`)或本地 MCP 翻译服务(`mcp_translate.py`)在批量下会被限流
(429/403),仅作备用。离线时也可直接人工填写第 3 列。
