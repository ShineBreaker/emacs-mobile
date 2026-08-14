# emacs-mobile

Android 原生 Emacs（GNU Emacs 30.2+，包名 `org.gnu.emacs`）触屏优化配置：以 Org 笔记与阅读为主用途，纯触屏 + `modifier-bar-mode` 交互。

架构：`early-init.el`（启动优化）+ `init.el`（模块入口）+ `modules/init-*.el`（基础 / 包管理 / Android 适配 / UI / 触屏 / 补全 / Org / 阅读 / 终饰）。

> 设计依据见 PLAN.md（不入库）。交互采用「方案 D」：底部单栏，mode-line 右端 `[kbd]` / `[cmd]` 块在 tool-bar（命令态）与 modifier-bar（输入态）间切换。

## 1. APK 选择

下载 `https://ftp.gnu.org/gnu/emacs/android/termux/` 下的 arm64-v8a APK（**termux 子目录版**，可与 Termux 共享签名后调用其 git 等命令）。⚠️ 待真机验证：具体文件名与 30.2 版本的对应关系。

## 2. Termux 签名兼容 ⚠️ 待真机验证

termux 版 Emacs 与 Termux 共享签名后才能 exec 其二进制（否则 `CANNOT LINK EXECUTABLE`）。重签流程**未实测**，实测后回填本节。在验证完成前，配置在无 Termux 环境下也能运行（外部命令守卫自动降级）。

## 3. 权限

设置 → 特殊应用访问 → 所有文件访问 → 授予 Emacs。此后 `/storage/emulated/0/`（= `/sdcard/`）可 POSIX 直读直写。

## 4. 部署

```sh
# 在 Termux 中（或 adb push）
git clone <本仓库> ~/.emacs.d
```

首次启动 straight 自动走镜像装包（耗时数分钟）。org 笔记目录：配置探测 `/storage/emulated/0/Data/Synching/notebook/org/`（拼写待真机确认），存在则使用；不存在则回退 `~/.emacs.d/org/`。

## 5. org-roam 首次建库

```elisp
M-x org-roam-db-sync   ; 从 org 文件重建 db（db 不随 Syncthing 同步）
```

⚠️ 待真机验证：`(featurep 'sqlite3)`（内置 sqlite 模块可用性）。

## 6. 镜像源

- ELPA/MELPA：默认 TUNA，改 `modules/init-packages.el` 里的 `custom/elpa-mirror`（`'tuna` / `'ustc` / `nil` 官方）。
- straight recipe 仓库：官方 elpa mirror（已开启）。
- GitHub 代理：`custom/github-proxy`（默认 nil 直连；仅作用于 bootstrap 脚本下载，git clone 加速待真机验证）。

## 7. 验证命令清单（真机执行）

```elisp
(eq system-type 'android)        ; => t
(window-system)                  ; => android
(executable-find "git")          ; Termux 协作是否生效
(native-comp-available-p)        ; 预计 nil，配置不依赖 .eln
(featurep 'sqlite3)              ; org-roam 依赖
```

## 8. 常见问题

- **虚拟键盘遮挡**：tap 任意处唤出（`touch-screen-display-keyboard t`）；键盘与 magit/transient 的冲突已知，本项目未装 magit。
- **后台被杀**：系统设置中锁定后台 / 关闭对 Emacs 的电池优化。
- **底部栏切换闪动**：方案 D 切换会重算 frame 布局，若真机上明显需迭代。

## 桌面开发期验证（沙箱，不污染真实配置）

```sh
# 加载冒烟测试
HOME=$(pwd)/.sandbox emacs --batch \
  --eval "(setq user-emacs-directory \"$(pwd)/\")" \
  -l early-init.el -l init.el

# byte-compile 单模块（必须先加载完整配置，否则误报）
HOME=$(pwd)/.sandbox emacs --batch \
  --eval "(setq user-emacs-directory \"$(pwd)/\")" \
  -l early-init.el -l init.el \
  --eval '(byte-compile-file "modules/init-<name>.el")'

# 手机比例排版校验（18:9 ≈ 40×80）
tmux new-session -d -s mob -x 40 -y 80
tmux send-keys -t mob \
  "HOME=$(pwd)/.sandbox TERM=xterm-256color emacs -nw --init-directory=$(pwd)" Enter
```

Android 特化全部在 `(when custom:android-p ...)` 守卫内，桌面加载自动跳过。
