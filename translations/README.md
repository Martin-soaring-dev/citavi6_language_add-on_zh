# translations/

存放本项目的中文译文。由 `tools/Extract-Resources.ps1` 从 Citavi 提取英文源后生成,人工/机翻结果保存在这里。

## 结构

```
translations/
├─ Citavi/                              (18 组)
├─ SwissAcademic/                       (1 组)
├─ SwissAcademic.Citavi/                (3 组)
├─ SwissAcademic.Citavi.WordAddIn/      (2 组)
├─ SwissAcademic.Controls/              (1 组)
├─ SwissAcademic.Resources/             (26 组,界面主体)
└─ SwissAcademic.WordProcessing/        (1 组)
```

共 **52** 个 TSV / **11,612** 条词条;覆盖约 **98.8%**(未译条目为设计上不译,运行时回退英文)。

## 格式

UTF-8(无 BOM),Tab 分隔,3 列:

```
key<TAB>English<TAB>中文
```

- `key`、`English` 由脚本维护,请勿手改。
- `中文` 留空 = 未翻译(运行时显示英文)。

详见 [../docs/03-translation-guide.md](../docs/03-translation-guide.md)。

> 重新提取需要本机安装 Citavi 6(见 `tools/Extract-Resources.ps1`);会保留已有中文列。
