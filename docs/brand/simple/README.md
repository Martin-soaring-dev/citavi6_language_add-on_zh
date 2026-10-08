# Citavi 6 中文语言包 — 品牌视觉资产
**文献之桥 / The Bridge of Literature** · Version 1.0 (2026-10-08)

这是社区独立制作的品牌视觉标识，非 Citavi 官方资产。所有 SVG 都是可编辑矢量元素，不含嵌入位图。

## 快速索引

- 完整规范：[视觉设计方案.md](视觉设计方案.md) / [VISUAL_IDENTITY.md](VISUAL_IDENTITY.md)
- 主标志发布版：[logo-primary-outlined.svg](svg/logo-primary-outlined.svg)
- 主标志可编辑字版：[logo-primary.svg](svg/logo-primary.svg)
- 横版：[logo-horizontal-outlined.svg](svg/logo-horizontal-outlined.svg)
- 独立透明符号：[logo-symbol.svg](svg/logo-symbol.svg)
- 深色完整版：[logo-dark-outlined.svg](svg/logo-dark-outlined.svg)
- 应用图标：[icon-light.svg](svg/icon-light.svg) / [icon-dark.svg](svg/icon-dark.svg)
- 单色版：[logo-monochrome-black.svg](svg/logo-monochrome-black.svg) / [logo-monochrome-white.svg](svg/logo-monochrome-white.svg)
- 视觉展示：[brand-overview.svg](preview/brand-overview.svg)

未加 `-outlined` 后缀的完整版保留可编辑 `<text>` 字标；发布版将字标轮廓化为路径。

完整原始效果图及 PNG 预览见交付的本地视觉资产 ZIP，仓库中以 SVG 源文件为主。

## Windows 分发物位图（安装包实际引用的文件）

由 [`tools/Build-BrandAssets.ps1`](../../../tools/Build-BrandAssets.ps1) 从上面的 SVG 生成，提交在 [`export/win/`](export/win/)：

| 文件 | 尺寸 | 被谁引用 |
|---|---|---|
| `export/win/setup.ico` | 16/24/32/48/64/128/256（PNG 帧） | `Setup.exe` 与卸载程序的文件图标、「应用和功能」卸载项图标 |
| `export/win/wizard-image.png` | 656 × 1256（= Inno 固定比例 164:314 的 4 倍） | Inno 欢迎页与安装完成页左侧大图 |
| `export/win/wizard-small.png` | 318 × 318（正方形） | Inno 内页右上角方图 |
| `export/win/logo-symbol.png` | 456 × 295 | ZIP 里 `Install-Gui.ps1` 窗体头部徽标 |

改过 `svg/` 后必须重跑 `pwsh ./tools/Build-BrandAssets.ps1` 并把位图一起提交，否则安装程序用的还是旧图。
后三张是透明底：Inno 向导面板与窗体底色会透过来，所以不要给它们加白底。

## 2026-10-08 SVG 显示修复

- 横版 `logo-horizontal.svg` 与 `logo-horizontal-outlined.svg`：加宽 viewBox，调整 `6` 的定位，保证字标和英文副标题不重叠、不被裁切。
- 三种应用图标 `icon-light.svg`、`icon-dark.svg`、`icon-monochrome.svg`：修正书本的水平偏移，统一居中（512 × 512）。
- `logo-monochrome-white.svg`、`logo-monochrome-white-outlined.svg`：使用**白色书页/文字和深蓝负形**，提供自带深蓝底的白色单色印刷展示版本。深蓝底是该文件的一部分，不是透明底。
- 可编辑字标版与轮廓版保持并行；白色单色版根据黑色单色版的几何形状进行颜色反转，不再使用与底色相同的书页填色。
