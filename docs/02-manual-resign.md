# 手动重签 Termux APK 指南

> 整理自 johanwiden/termux-for-android-emacs README（实测记录）与 emacs-mobile 参考笔记。
> 原理见 [01-shared-uid-mechanism.md](01-shared-uid-mechanism.md)。
> 本仓库的 CI 脚本（`scripts/`）已把以下流程自动化，不想手动做请看 [03-github-action.md](03-github-action.md)。

## 0. 前置工具

只需 `apksigner`（Android SDK build-tools 组件）：

```sh
# Termux 内
pkg install apksigner

# 桌面 Linux：安装 Android SDK cmdline-tools 后
sdkmanager --install "build-tools;34.0.0"
# 之后使用 $ANDROID_HOME/build-tools/34.0.0/apksigner
```

> 反编译重建（apktool）与 zipalign 步骤已不再需要：直接对官方 APK 重签即可。

## 1. 获取密钥

直接用本仓库的 [assets/emacs.keystore](../assets/emacs.keystore)，或从 Emacs 源码树下载：

```sh
curl -fLO https://raw.githubusercontent.com/emacs-mirror/emacs/master/java/emacs.keystore
```

密钥库密码 `emacs1`（公开信息）。证书 SHA-256 指纹应为：

```
50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604
```

## 2. 下载 Termux APK

两个渠道任选：

**渠道 A：GitHub 预览版**（[termux/termux-app releases](https://github.com/termux/termux-app/releases)，标记为 _Pre-release_，即本仓库 CI 抓取的来源）

资产命名规则：`termux-app_<tag>+<flavor>-<buildtype>_<abi>.apk`

| 字段      | 取值                                                         | 选择建议                                                                              |
| --------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| flavor    | `apt-android-7` / `apt-android-5`                            | 现代设备一律 `apt-android-7`（Android 7+）；`apt-android-5` 仅用于 Android 5/6 老设备 |
| buildtype | `github-debug`（目前 GitHub Release 仅提供此构建）           | 无需选择                                                                              |
| abi       | `universal` / `arm64-v8a` / `armeabi-v7a` / `x86_64` / `x86` | `universal` 全设备通用；ABI 与设备不符会导致子进程执行失败                            |

每个 flavor-buildtype 组合另附 `_sha256sums` 资产，下载后应校验。

**渠道 B：F-Droid**（<https://f-droid.org/en/packages/com.termux/>，稳定版）

johanwiden 实测记录：F-Droid 版 `0.119.0-beta.3 (1022)`（2025-05-29 上架）重签后在 Android 15 的 OnePlus Open 与 Samsung Tab S8+ 上可用。

## 3. 重签

```sh
apksigner sign --v2-signing-enabled \
  --ks emacs.keystore -debuggable-apk-permitted \
  --ks-pass pass:emacs1 \
  --out termux-emacs-signed.apk \
  termux-app_v0.119.0-beta.3+apt-android-7-github-debug_universal.apk
```

参数说明（与 Emacs 源码 `java/Makefile.in` 的 `SIGN_EMACS_V2` 一字不差）：

- `--v2-signing-enabled`：启用 APK Signature Scheme v2（Android 7.0+）
- `-debuggable-apk-permitted`：允许给 debuggable APK 签名。GitHub 预览版是 `github-debug` 构建（manifest 带 `android:debuggable`），必须带此参数
- `--ks-pass pass:emacs1`：Emacs 公开密钥库的密码

## 4. 验证签名

```sh
apksigner verify --print-certs termux-emacs-signed.apk
```

输出的 `Signer #1 certificate SHA-256 digest` 必须等于第 1 步的指纹。

## 5. 安装顺序与升级规则

**首次安装 / 从官方签名版切换**（sharedUserId 的安装顺序约束，顺序不能反）：

1. 备份并卸载已有的 Emacs 与 Termux——**卸载会清掉各自数据目录**
2. **先**安装重签版 Termux APK
3. **再**安装 termux 版 Emacs APK（<https://ftp.gnu.org/gnu/emacs/android/termux/>，文件名规则 `emacs-<版本>-<最低AndroidAPI>-<ABI>.apk`，如 `emacs-30.2-29-arm64-v8a.apk`）
4. 打开 Termux 执行 `pkg update && pkg upgrade`，之后 `pkg install git` 等即可在 Emacs 内使用

**升级规则**：

- 重签版与官方签名不同，**无法从 Termux 官方渠道（F-Droid/Play）覆盖升级**，升级时用新版本 APK 重签后覆盖安装（同签名可覆盖）
- termux 版 Emacs 与 GNU 独立版 Emacs（非 termux 目录的 APK）**不能共存**，切换需先卸载
- 权限：设置 → 特殊应用访问 → 所有文件访问 → 授予 Emacs，此后 `/storage/emulated/0/`（= `/sdcard/`）可直读直写

## 6. 装机验证清单（在 Emacs 里执行）

```elisp
(eq system-type 'android)        ; => t
(window-system)                  ; => android
(executable-find "git")          ; => 非 nil，说明 Termux 协作生效
(native-comp-available-p)        ; 预计 nil，Android 版不依赖 .eln
(featurep 'sqlite3)              ; org-roam 依赖（待真机确认）
```
