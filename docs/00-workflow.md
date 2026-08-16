自动抓取 [termux/termux-app](https://github.com/termux/termux-app) 的 GitHub **预览版** APK，用 GNU Emacs 官方公开构建密钥重签后发布为本仓库 Release，供 [Android 原生 Emacs](https://ftp.gnu.org/gnu/emacs/android/)（`org.gnu.emacs`）通过 `sharedUserId` 共享 UID、直接使用 Termux 内的程序（git 等）。

**原理**：termux 版 Emacs 与 Termux 都声明了 `sharedUserId`，Android 只给**同签名**的包分配同一 UID。Emacs 官方公开了自己的构建密钥（`emacs.keystore`，密码 `emacs1`），重签 Termux 即可互通。详见 [docs/01-shared-uid-mechanism.md](docs/01-shared-uid-mechanism.md)。

## 使用

1. 到本仓库 [Releases](../../releases) 页下载最新 `*-emacs-signed.apk`
2. 按安装顺序装好 Emacs 与 Termux（**先 Termux 后 Emacs**，细节见 [docs/02-manual-resign.md](docs/02-manual-resign.md)）

没有所需版本时，在 Actions 页手动触发 _Resign Termux prerelease_ 工作流（无需任何 Secrets 配置），或本地用 `just` 一条龙（详见 [docs/03-github-action.md](docs/03-github-action.md)）：

```sh
just termux  # 自动准备 apksigner → 抓最新预览版 → 校验 → 重签，产物在 download/
```

依赖齐全的环境开箱即用（Guix 实测通过）；缺依赖时可在容器中运行（如 `distrobox enter my-distrobox`），已装 Android SDK 的系统可 `export APKSIGNER=apksigner`。

## 仓库结构

```
docs/                              # 整理自 ref/ 原始资料的规范文档（ref/ 不入库）
├── 01-shared-uid-mechanism.md     # sharedUserId 同签名机制
├── 02-manual-resign.md            # 手动重签完整指南
└── 03-github-action.md            # 本仓库工作流使用说明
scripts/
├── fetch-termux-prerelease.sh     # 抓取上游预览版 APK + sha256 校验
└── resign-apk.sh                  # Emacs 密钥重签 + 证书指纹断言
justfile                           # 本地命令包装（tools/fetch/resign/termux/clean）
assets/
└── emacs.keystore                 # Emacs 官方公开构建密钥（PKCS12，密码 emacs1）
.github/workflows/
└── resign-termux.yml              # 自动抓取-重签-发布工作流
```

> 本仓库密钥文件与密码均为 Emacs 官方源码树（`java/` 目录）公开分发的内容，无保密性可言；这也是该机制的设计前提——任何人都能签出与官方 Emacs 一致的签名。
