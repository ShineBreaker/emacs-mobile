# emacs-mobile

Android 原生 Emacs（GNU Emacs 30.2+，包名 `org.gnu.emacs`）触屏优化配置：以 Org 笔记与阅读为主用途，纯触屏交互。

架构：`early-init.el`（启动优化）+ `init.el`（模块入口）+ `modules/init-*.el`（基础 / 包管理 / UI / 触屏 / 工具栏 / 补全 / Org / Markdown / 仪表盘 / 阅读 / 终饰）。本仓库同时维护 **Termux 自动重签流水线**（GitHub Action + `just` + `scripts/`），用于产出与 Emacs 同签名的 Termux APK，见 [docs/00-workflow.md](docs/00-workflow.md)。

> 交互组件用**官方组件分层**：**tool-bar**（底部，官方）承载全局命令——[修饰键栏开关] 打开/保存/复制/粘贴/剪切/搜索/深浅主题/配置文件夹(dired)/仪表盘（10 钮；撤销/重做走 M-x，回中在 mode-line 右端），图标为 [Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) symbolic 矢量 SVG（加载时按深浅主题重着色直渲，无 librsvg 构建回退中灰 PNG 兜底；`just icons` 幂等重建，上游 GPL-3.0，来源见 data/icons/README.md；复制剪切有选区作用于选区、无选区作用于当前行）；**modifier-bar**（官方）承载修饰键（tap 后下一个输入带修饰）；**mode-line** 承载 buffer/窗口控制——✕ 关闭当前 buffer 及其窗口（仅剩主窗时只关 buffer）、换 切换缓冲区。启动显示**仪表盘**（braille 点阵 banner + navigator 入口 [抓笔记] [议程] [Roam 笔记]；最近文件按目录首字母缩写显示、本周日程、最近 Roam 笔记，条目直接点按打开）。

## 1. APK 选择

termux 版 Emacs 在 `https://ftp.gnu.org/gnu/emacs/android/termux/`（国内镜像：[阿里云](https://mirrors.aliyun.com/gnu/emacs/android/termux/)），文件名规则 `emacs-<版本>-<最低Android API>-<ABI>.apk`。现代 arm 手机选 `emacs-30.2-29-arm64-v8a.apk`（Android 10+）；ABI 与设备不符会导致子进程执行失败。termux 版与根目录独立版 Emacs **不能共存**，切换需先卸载。

## 2. Termux 签名兼容

机制：termux 版 Emacs 与 Termux 的 manifest 都声明 `sharedUserId`，Android 只给**同签名**的包分配同一 UID，Emacs 才能执行 Termux 内的程序（git 等）。F-Droid/Play/GitHub 版 Termux 签名各不相同，不能直接混用，也无法跨签名覆盖升级。详见 [docs/01-shared-uid-mechanism.md](docs/01-shared-uid-mechanism.md)。

获取与 Emacs 同签名的 Termux，按省事程度：

1. **本仓库流水线产物（推荐）**：到 [Releases](../../releases) 下载最新 `*-emacs-signed.apk`。GitHub Action 每周自动检查 [termux/termux-app](https://github.com/termux/termux-app) 预览版，经官方 sha256 校验后用 Emacs 公开构建密钥（`assets/emacs.keystore`）重签、断言证书指纹再发布（已发布过的版本直接跳过），无需配置任何 Secrets。没有所需版本时到 Actions 页手动触发 _Resign Termux prerelease_（可选 tag/flavor/abi/force），或本地一条龙：

   ```sh
   just termux  # 自动准备 apksigner → 抓最新预览版 → 校验 → 重签，产物在 download/
   ```

   细节见 [docs/00-workflow.md](docs/00-workflow.md) 与 [docs/03-github-action.md](docs/03-github-action.md)。

2. **官方同签名版**：[SourceForge: android-ports-for-gnu-emacs](https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/) 的 `termux-app_apt-android-7-release_universal.apk`，无需任何签名操作，但版本较旧（不支持 Android 16）。

3. **手动重签**：完整指南（密钥获取、签名命令参数、指纹校验、渠道选择）见 [docs/02-manual-resign.md](docs/02-manual-resign.md)。

安装（流程来自 [GNU 官方 README](https://ftp.gnu.org/gnu/emacs/android/README)）：

1. 备份并卸载已有的 Emacs 与 Termux（卸载会清数据目录）
2. **先**装 Termux（上述任一同签名版本）
3. **再**装 GNU termux 目录的 Emacs APK（顺序不能反）
4. 打开 Termux 执行 `pkg update && pkg upgrade`，之后 `pkg install git` 等即可在 Emacs 内使用

升级注意：重签版签名与官方不同，无法从 F-Droid/Play 覆盖升级，只能用新版本 APK 重签后覆盖安装（本仓库流水线每周跟进上游预览版，已发布版本自动跳过）。

装好后在 Emacs 侧无需额外配置：本配置 `early-init.el` 已按官方建议把 `/data/data/com.termux/files/usr/bin` 注入 `PATH`/`exec-path`。**不要设置 `LD_LIBRARY_PATH`**（官方 README 明确旧 FAQ 的该建议是错的，会导致系统库与 Termux 库冲突）。上述流程未在本机真机实测，装完后按 §7 清单验证。

## 3. 权限

设置 → 特殊应用访问 → 所有文件访问 → 授予 Emacs。此后 `/storage/emulated/0/`（= `/sdcard/`）可 POSIX 直读直写。

## 4. 部署

完整仓库 clone 在 Termux home 的 `~/.config/emacs`（git 可用），Emacs 自身的 `~/.emacs.d`（`/data/data/org.gnu.emacs/files/.emacs.d/`）只放两个入口文件的副本：

```sh
# Termux 中执行
git clone <本仓库> ~/.config/emacs
mkdir -p /data/data/org.gnu.emacs/files/.emacs.d
cp ~/.config/emacs/early-init.el ~/.config/emacs/init.el \
   /data/data/org.gnu.emacs/files/.emacs.d/
```

加载链路：Emacs home 的 `early-init.el` 探测到 Termux 仓库后重定向 `user-emacs-directory` 并加载仓库版本；`init.el` 的加载位置虽不随重定向变化（Emacs 机制，已实测），但此时 `user-emacs-directory` 已指向仓库，require 的即 Termux 仓库中的 modules。两个入口文件更新后需重新复制。

数据均不进仓库（`custom:data-home`：Android=Termux home，桌面沙箱=HOME）：straight 缓存 `~/.cache/emacs/straight/`，org-roam db `~/.cache/emacs/org-roam.db`，recentf/savehist/saveplace/主题状态 `~/.local/state/emacs/`。

在 Termux 里安装 Termux 版 Emacs（`pkg install emacs`）时，它会按 XDG 惯例直接加载 `~/.config/emacs` 的同一套配置（触屏特化自动跳过，`system-type` 非 android）——手机上两版 Emacs 共用配置，后续可按需调优。

### 排查

启动报错或行为异常时，先在 Emacs 里执行 `M-x custom/deploy-diagnose`：它会弹出 buffer 列出部署链路各环节状态（Termux home 可访问性、仓库与 modules 存在性、`user-emacs-directory` 重定向结果）并给出结论与修复指引。init 加载失败的报错信息本身也会带根因结论。

### 依赖一键补全

先装 Termux 基础依赖：`pkg install git`（clone 仓库用）。然后在本仓库目录执行 `just emacs`，一键补全全部配置侧依赖（Termux 包 → 字体 → 图标 → 插件预构建）；其中 `just termux-deps` 单独负责 Termux 包安装（桌面环境自动跳过）：

```sh
just emacs    # termux-deps → font → icons → packages，一条命令补全
```

- `just termux-deps`：Termux 里安装配置侧依赖包 `curl unzip fontconfig emacs git sqlite ripgrep`（包名已按 termux-packages 源核实；curl/sqlite 为 libcurl/libsqlite 子包，sqlite3 无独立包）
- `just font`：下载 [Maple Mono NF CN](https://github.com/subframe7536/maple-font)（中英等宽主字体）→ Android 装到 Emacs home 的 `fonts/`（sfnt-android 启动时枚举，装后重启 Emacs 生效），桌面装到 fontconfig 用户目录；已装则跳过
- `just icons`：生成 tool-bar 图标（Papirus symbolic SVG + 72px PNG 兜底，`data/icons/` 已随仓库分发，真机无需执行；缺失时在装有 librsvg `rsvg-convert` 的桌面重建）
- `just packages`：跑一遍完整 init 预构建全部插件（真机缓存 `~/.cache/emacs/straight`，桌面 `.sandbox/`）

首次启动 straight 自动走镜像装包（耗时数分钟）。org 笔记目录：配置探测 `/storage/emulated/0/Data/Syncthing/notebook/org/`，存在则使用；不存在则回退 `~/.emacs.d/org/`（桌面沙箱全功能测试用）。

## 5. org-roam 首次建库

```elisp
M-x org-roam-db-sync   ; 从 org 文件重建 db（db 不随 Syncthing 同步）
```

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
(executable-find "sqlite3")  ; org-roam 依赖（CLI 后端，非内置模块）
```

## 8. 常见问题

- **安装报 `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`**：设备上有包占着 `com.termux` 共享用户且签名不同，最常见原因是 **Termux 插件残留**（Termux:API/Widget/Boot/Float 同样声明 `sharedUserId="com.termux"`，只卸主应用不够）。把 Termux 系应用全部卸载（必要时重启手机），再按先 Termux 后 Emacs 的顺序安装。
- **虚拟键盘遮挡**：tap 任意处唤出（`touch-screen-display-keyboard t`）；键盘与 magit/transient 的冲突已知，本项目未装 magit。
- **启动弹 `Emergency (magit): Magit requires 'transient' >= 0.13 ...`**：org-roam 依赖的 `magit-section`（取 magit 仓库 HEAD）自身 require 新版 transient，Emacs 30.2 内置旧版触发。配置已装 GNU ELPA stable `transient` 覆盖内置（init-org），新克隆环境不再出现；旧环境仍弹出则多为缓存残留，Termux 里执行后重启 Emacs：
  ```sh
  rm -rf ~/.cache/emacs/straight/build/magit-section ~/.cache/emacs/straight/build/magit
  ```
- **启动后无响应/卡死**：先看 echo area 与 `*Warnings*`（`⛔ Error (use-package <模块>/<阶段>)` 直接指明出错模块与阶段）。疑似 org-roam 库卡住时，在 Termux 里三件套取证：
  ```sh
  ps -ef | grep -E "emacs|sqlite3"   # 残留 sqlite3 子进程 = 持库锁
  ls -la ~/.cache/emacs/             # org-roam.db-journal 存在 = 写事务未提交
  top -n 1 | head                     # emacs CPU 满载 = elisp 长计算
  ```
  库损坏或锁死时删 `~/.cache/emacs/org-roam.db` 重建：保存笔记后自动增量补录，或 `M-x org-roam-db-sync` 手动全量（有进度、可预期）。
- **启动加载 org 时提示 `WARNING: No org-loaddefs.el file ...` 并停顿数秒**：缓存里混入了 git 版 org（org-roam 的依赖链经 org-elpa recipe 拉入，`:straight nil` 拦不住依赖层），其 build 缺 make 产物 org-loaddefs.el，且排在 load-path 首位挤掉内置 org。修复（Termux 里执行后重启 Emacs）：
  ```sh
  rm -rf ~/.cache/emacs/straight/build/org ~/.cache/emacs/straight/repos/org
  ```
  配置已把 org recipe 覆盖为内置（`init-packages.el`），之后依赖解析不会再装回。
- **后台被杀**：系统设置中锁定后台 / 关闭对 Emacs 的电池优化；厂商定制系统的额外限制见 [dontkillmyapp.com](https://dontkillmyapp.com/)。
- **Termux 子进程被周期性杀掉（Android 12+）**：系统「幽灵进程杀手」每 5 分钟检查并终止 CPU 占用最高的后台子进程——straight 的 git、org-roam 的 sqlite3 CLI、consult-ripgrep 都可能中招（表现为间歇性失败、db 查询报错）。用 adb 关闭（手机开启「USB 调试」后在电脑执行）：
  ```sh
  adb shell "settings put global settings_enable_monitor_phantom_procs false"
  ```
- **init 出错无法启动（官方逃生通道）**：Android 无命令行参数，可用系统设置里 Emacs 的偏好设置界面以 `--quick`（跳过 init）或 `--debug-init` 启动（Android 7+：设置 → 应用 → Emacs 的应用信息页入口；旧系统：桌面「Emacs options」图标，因厂商而异）。若报转储文件（dump file）损坏，同一界面可删除 Emacs 文件目录中的转储文件修复；也可用任意文件管理器经 Emacs 导出的 documents provider 直接改名/删除 init 文件。
- **从其他 app 打开文件**：emacsclient 包装程序把文件转交给运行中的 Emacs 会话，要求 server 在跑（配置已在 Android 下默认启用，见 init-misc.el）；Emacs 未运行时首次打开会拉起完整启动，之后即可正常转交。
- **底部栏切换闪动**：切换会重算 frame 布局，若真机上明显需迭代。

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
