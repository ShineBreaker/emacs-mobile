# emacs-mobile

Android 原生 Emacs（GNU Emacs 30.2+，包名 `org.gnu.emacs`）触屏优化配置：以 Org 笔记与阅读为主用途，纯触屏 + `modifier-bar-mode` 交互。

架构：`early-init.el`（启动优化）+ `init.el`（模块入口）+ `modules/init-*.el`（基础 / 包管理 / Android 适配 / UI / 触屏 / 补全 / Org / 阅读 / 终饰）。

> 设计依据见 PLAN.md（不入库）。交互采用「方案 D」：底部单栏，mode-line 右端 `[kbd]` / `[cmd]` 块在 tool-bar（命令态）与 modifier-bar（输入态）间切换。

## 1. APK 选择

termux 版 Emacs 在 `https://ftp.gnu.org/gnu/emacs/android/termux/`（国内镜像：[阿里云](https://mirrors.aliyun.com/gnu/emacs/android/termux/)），文件名规则 `emacs-<版本>-<最低Android API>-<ABI>.apk`。现代 arm 手机选 `emacs-30.2-29-arm64-v8a.apk`（Android 10+）；ABI 与设备不符会导致子进程执行失败。termux 版与根目录独立版 Emacs **不能共存**，切换需先卸载。

## 2. Termux 签名兼容

机制：termux 版 Emacs 与 Termux 的 manifest 都声明 `sharedUserId`，两个 APK 只有用**同一签名密钥**签名才会被系统分配同一 UID，Emacs 才能执行 Termux 内的程序（git 等）。F-Droid/GitHub 版 Termux 签名不同，不能直接混用（也无法覆盖升级）。

**路线一（推荐，无需任何签名操作）**：官方已提供与 Emacs 同签名的 Termux 本体，流程来自 [GNU 官方 README](https://ftp.gnu.org/gnu/emacs/android/README)：

1. 备份并卸载已有的 Emacs 与 Termux（卸载会清数据目录）
2. **先**安装 [SourceForge: android-ports-for-gnu-emacs](https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/) 提供的 `termux-app_apt-android-7-release_universal.apk`
3. **再**安装 GNU termux 目录的 Emacs APK（顺序不能反）
4. 打开 Termux 执行 `pkg update && pkg upgrade`，之后 `pkg install git` 等即可在 Emacs 内使用

**路线二（需要更新版 Termux 时自行重签）**：官方 Termux 版本较旧（不支持 Android 16）。用 Emacs 公开构建密钥重签 F-Droid 版 Termux（密钥库密码 `emacs1`，密钥取自 [emacs-mirror/emacs](https://github.com/emacs-mirror/emacs) 的 `java/` 目录）：

```sh
pkg install apksigner
apksigner sign --v2-signing-enabled \
  --ks emacs.keystore -debuggable-apk-permitted \
  --ks-pass pass:emacs1 com.termux_1022.apk
```

也可直接使用 [johanwiden/termux-for-android-emacs](https://github.com/johanwiden/termux-for-android-emacs) 已签好的 Termux 0.119.0-beta（Android 15 实测可用）。重签版今后无法从 Termux 官方渠道覆盖升级，只能继续自签。

装好后在 Emacs 侧无需额外配置：本配置 `early-init.el` 已按官方建议把 `/data/data/com.termux/files/usr/bin` 注入 `PATH`/`exec-path`。**不要设置 `LD_LIBRARY_PATH`**（官方 README 明确旧 FAQ 的该建议是错的，会导致系统库与 Termux 库冲突）。上述流程未在本机真机实测，装完后按 §7 清单验证。

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
