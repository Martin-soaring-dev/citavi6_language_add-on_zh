# translations/

存放本项目的中文译文。由 `tools/Extract-Resources.ps1` 从 Citavi 提取英文源后生成,人工/机翻结果保存在这里。

## 结构(计划)

```
translations/
├─ SwissAcademic.Resources/
│  ├─ Strings.tsv
│  ├─ ControlTexts.tsv
│  ├─ Tools.tsv
│  ├─ Enums.tsv
│  ├─ WebLabels.tsv
│  ├─ ReferenceTypeLabels.tsv
│  ├─ StyleEditor.tsv
│  └─ ... (其余资源组)
├─ SwissAcademic.Controls/
├─ SwissAcademic.Citavi/
├─ SwissAcademic/
└─ SwissAcademic.WordProcessing/
```

## 格式

UTF-8(无 BOM),Tab 分隔,3 列:

```
key<TAB>English<TAB>中文
```

- `key`、`English` 由脚本维护,请勿手改。
- `中文` 留空 = 未翻译(运行时显示英文)。

详见 [../docs/03-translation-guide.md](../docs/03-translation-guide.md)。

> 当前为空骨架。生成英文源文件需要本机安装 Citavi 6(见 `tools/Extract-Resources.ps1`)。
