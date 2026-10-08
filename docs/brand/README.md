# 品牌视觉方案 / Brand Identity Versions

这里集中管理 [Citavi 6 中文语言包](../../README.md) 项目的所有 Logo 方案。**每个方案独立成目录**，保留自己的源文件、预览和视觉规范，避免后续迭代覆盖已有设计。

## 方案列表

| 方案目录 | 名称 | 风格 | 状态 | 资源 |
|---|---|---|---|---|
| [`simple/`](simple/README.md) | 文献之桥 · The Bridge of Literature | 蓝红开卷、C + 中、书签 | 安装程序与图形安装器采用 | [SVG 图标](simple/svg/logo-symbol.svg) · [主标志](simple/svg/logo-primary-outlined.svg) · [Windows 位图](simple/export/win/) · [规范](simple/视觉设计方案.md) |

## 版本目录规范

```text
docs/brand/
├── README.md                  # 方案索引（本文件）
├── simple/                    # 当前方案：文献之桥
│   ├── README.md              # 用途与资产清单
│   ├── VISUAL_IDENTITY.md     # 视觉规范
│   ├── 视觉设计方案.md
│   ├── svg/                   # 可编辑/轮廓化图标
│   ├── export/win/            # 安装包与图形安装器用的位图(脚本生成,入库)
│   └── preview/               # SVG 预览
└── <future-version>/          # 以后新增其他候选方案
```

后续要新增一套设计时，创建单独的 `docs/brand/<version>/`，并在上方表格补充其名称、预览和状态。**不要覆盖其他方案的 SVG 和规范**。

## 注意

- 本目录为社区项目的非官方标识，不代表 Citavi 官方认可或背书。
- `simple/export/win/` 下的位图**已经是分发物的一部分**：`Setup.exe` 的文件图标与向导页、ZIP 里的图形安装器都引用它们。改动 `svg/` 后必须重跑 `tools/Build-BrandAssets.ps1` 并把生成的位图一起提交。
- 原路径 `docs/brand/svg/`、`docs/brand/preview/` 已迁移到 `docs/brand/simple/`，引用时应使用新路径。
