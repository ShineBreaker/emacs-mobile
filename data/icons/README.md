# tool-bar 图标（data/icons/）

来源：[Papirus icon theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)
tag `20260801` 的 24×24 symbolic 系列（单色、`ColorScheme-Text` CSS 变量着色）。
上游许可证 **GPL-3.0**（见上游仓库 LICENSE）；`.svg` 为原样副本，
`.png` 为管线内重着色（#808080）后 72px 光栅化的兜底资产。

由 justfile `icons` 配方生成（幂等，缺啥补啥）；按钮与图标名的映射
见该配方内 `spec` 表，运行端加载与主题重着色见 `modules/init-bar.el`。

| 按钮 | Papirus 图标 |
| --- | --- |
| modbar | devices/input-keyboard-symbolic |
| open | actions/document-open-symbolic |
| save | actions/document-save-symbolic |
| copy | actions/edit-copy-symbolic |
| paste | actions/edit-paste-symbolic |
| cut | actions/edit-cut-symbolic |
| search | actions/edit-find-symbolic |
| theme | status/night-light-symbolic |
| config | places/folder-symbolic |
| quick | actions/feather-zap-symbolic |

另有一组 **modifier-bar 徽章** `mod-*.png`（168×96 描边文字徽章：
Ctrl/Shift/Meta/Alt/Sup/Hyp/Tab/Esc，中灰、双主题通吃）——非 Papirus
资产，由管线用 Maple 字形直接绘制（官方六修饰键原图是 35×19 PBM 位图
徽章，整套重建统一风格，见 `modules/init-touch.el`）。
