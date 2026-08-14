# emacs-mobile

Android 原生 Emacs（GNU Emacs 30.2+，包名 `org.gnu.emacs`）触屏优化配置：以 Org 笔记与阅读为主用途，纯触屏 + `modifier-bar-mode` 交互。

架构：`early-init.el`（启动优化）+ `init.el`（模块入口）+ `modules/init-*.el`（基础 / 包管理 / Android 适配 / UI / 触屏 / 补全 / Org / 阅读 / 终饰）。本仓库同时维护 **Termux 自动重签流水线**（GitHub Action + `just` + `scripts/`），用于产出与 Emacs 同签名的 Termux APK，见 [docs/00-workflow.md](docs/00-workflow.md)。

> 设计依据见 PLAN.md（不入库）。交互采用「方案 D」：底部单栏，mode-line 右端 `[kbd]` / `[cmd]` 块在 tool-bar（命令态）与 modifier-bar（输入态）间切换。

## 1. APK 选择

termux 版 Emacs 在 `https://ftp.gnu.org/gnu/emacs/android/termux/`（国内镜像：[阿里云](https://mirrors.aliyun.com/gnu/emacs/android/termux/)），文件名规则 `emacs-<版本>-<最低Android API>-<ABI>.apk`。现代 arm 手机选 `emacs-30.2-29-arm64-v8a.apk`（Android 10+）；ABI 与设备不符会导致子进程执行失败。termux 版与根目录独立版 Emacs **不能共存**，切换需先卸载。

## 2. Termux 签名兼容

机制：termux 版 Emacs 与 Termux 的 manifest 都声明 `sharedUserId`，Android 只给**同签名**的包分配同一 UID，Emacs 才能执行 Termux 内的程序（git 等）。F-Droid/Play/GitHub 版 Termux 签名各不相同，不能直接混用，也无法跨签名覆盖升级。详见 [docs/01-shared-uid-mechanism.md](docs/01-shared-uid-mechanism.md)。

获取与 Emacs 同签名的 Termux，按省事程度：

1. **本仓库流水线产物（推荐）**：到 [Releases](../../releases) 下载最新 `*-emacs-signed.apk`。GitHub Action 每日自动抓取 [termux/termux-app](https://github.com/termux/termux-app) 预览版，经官方 sha256 校验后用 Emacs 公开构建密钥（`assets/emacs.keystore`）重签、断言证书指纹再发布，无需配置任何 Secrets。没有所需版本时到 Actions 页手动触发 _Resign Termux prerelease_（可选 tag/flavor/abi/force），或本地一条龙：

   ```sh
   just build    # 自动准备 apksigner → 抓最新预览版 → 校验 → 重签，产物在 download/
   ```

   细节见 [docs/00-workflow.md](docs/00-workflow.md) 与 [docs/03-github-action.md](docs/03-github-action.md)。

2. **官方同签名版**：[SourceForge: android-ports-for-gnu-emacs](https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/) 的 `termux-app_apt-android-7-release_universal.apk`，无需任何签名操作，但版本较旧（不支持 Android 16）。

3. **手动重签**：完整指南（密钥获取、签名命令参数、指纹校验、渠道选择）见 [docs/02-manual-resign.md](docs/02-manual-resign.md)。

安装（流程来自 [GNU 官方 README](https://ftp.gnu.org/gnu/emacs/android/README)）：

1. 备份并卸载已有的 Emacs 与 Termux（卸载会清数据目录）
2. **先**装 Termux（上述任一同签名版本）
3. **再**装 GNU termux 目录的 Emacs APK（顺序不能反）
4. 打开 Termux 执行 `pkg update && pkg upgrade`，之后 `pkg install git` 等即可在 Emacs 内使用

升级注意：重签版签名与官方不同，无法从 F-Droid/Play 覆盖升级，只能用新版本 APK 重签后覆盖安装（本仓库流水线每日跟进上游预览版）。

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

- **安装报 `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`**：设备上有包占着 `com.termux` 共享用户且签名不同，最常见原因是 **Termux 插件残留**（Termux:API/Widget/Boot/Float 同样声明 `sharedUserId="com.termux"`，只卸主应用不够）。把 Termux 系应用全部卸载（必要时重启手机），再按先 Termux 后 Emacs 的顺序安装。
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
