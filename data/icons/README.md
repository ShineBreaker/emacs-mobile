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
| save | actions/document-save-symbolic |
| copy | actions/edit-copy-symbolic |
| cut | actions/edit-cut-symbolic |
| paste | actions/edit-paste-symbolic |
| undo | actions/edit-undo-symbolic |
| redo | actions/edit-redo-symbolic |
| search | actions/edit-find-symbolic |
| recenter | actions/format-justify-center-symbolic |
| theme | status/night-light-symbolic |
| config | actions/lucide-wrench-symbolic |
| dashboard | actions/view-grid-symbolic |
