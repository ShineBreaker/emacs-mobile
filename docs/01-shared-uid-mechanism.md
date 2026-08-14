# sharedUserId 同签名机制

> 整理自 marek-g 博客、johanwiden/termux-for-android-emacs README 与 emacs-mobile 参考笔记。

## 场景与问题

Android 原生 Emacs（GNU Emacs 30.2+ 的 Android 移植版，包名 `org.gnu.emacs`）自带完整 Emacs，但没有 shell 工具链。要在 Emacs 里用 `git`、grep、编程语言等，最自然的做法是借助 Termux 的环境。

障碍是 Android 的应用沙箱：每个应用有独立的数据目录和 Linux UID——

- Emacs 的数据在 `/data/data/org.gnu.emacs/`
- Termux 的数据在 `/data/data/com.termux/`，所有通过 `pkg install` 安装的工具都在其中的 `files/usr/` 下

UID 不同，Emacs 既看不到 Termux 装的程序，也无权执行它们。

## 机制：sharedUserId + 同签名

Android（旧版 API）的 manifest 属性 `android:sharedUserId` 允许多个 APK 声明共享同一个 Linux 用户：

1. Termux 的 manifest 本身就声明了 `android:sharedUserId="com.termux"`；
2. termux 版 Emacs 的 manifest 同样声明了该属性；
3. Android 在安装时校验：**声明同一 sharedUserId 的所有包必须使用同一证书签名**，通过后才给它们分配同一 UID。

因此两者互通的充要条件是：**用同一把密钥签名**。

签名不一致的实际后果：

- 系统不认账，两个包各拿各的 UID，Emacs 依然无法执行 Termux 内的程序；
- 已安装的 APK 无法被不同签名的版本覆盖升级（安装直接失败）；
- F-Droid 版、Google Play 版、GitHub 构建版 Termux 的签名各不相同，与 Emacs 官方签名均不兼容，不能直接混用。

## Emacs 官方公开了自己的构建密钥

这是整个方案成立的前提：GNU Emacs 把 Android 构建签名密钥**公开分发**在源码树的 [`java/emacs.keystore`](https://github.com/emacs-mirror/emacs/tree/master/java)（PKCS12 格式密钥库，storepass/keypass 均为 `emacs1`，alias 为 `emacs`）。

- 证书 SHA-256 指纹：`50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604`
- Emacs 源码 `java/Makefile.in` 中的官方签名命令（`SIGN_EMACS_V2`）：

  ```sh
  apksigner sign --v2-signing-enabled --ks emacs.keystore \
    -debuggable-apk-permitted --ks-pass pass:emacs1 <apk>
  ```

任何人都可以用这把公开密钥签出与官方 Emacs 完全相同签名的 APK——把 Termux 官方 APK 重签一遍即可（见 [02-manual-resign.md](02-manual-resign.md)）。johanwiden 用此方法重签的 Termux 0.119.0-beta.3 在 Android 15（OnePlus Open、Samsung Tab S8+）实测可用。

> 历史注：marek-g 的早期做法是用 apktool 反编译 Emacs APK、手工往 manifest 加 `sharedUserId` 再重建签名。如今 termux 版 Emacs 已自带该属性，**只需重签 Termux 一侧**，apktool 步骤不再需要。

## 获取 Termux 的两条路线

|          | 路线一：官方同签名版                                                                                                                                                       | 路线二：自行重签（本仓库所为）                |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| 来源     | [SourceForge: android-ports-for-gnu-emacs](https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/) 的 `termux-app_apt-android-7-release_universal.apk` | 任一渠道的 Termux APK + `emacs.keystore` 重签 |
| 签名操作 | 无需任何操作                                                                                                                                                               | 需要 apksigner（本仓库 CI 全自动）            |
| 版本     | 较旧（据 emacs-mobile 笔记，不支持 Android 16）                                                                                                                            | 可跟进任意版本，含 GitHub 预览版              |

两条路线**互斥**：升级时必须先卸载旧 Termux（同签名约束决定了不能跨签名覆盖安装）。

## Emacs 侧的配套配置

装好同签名 Termux 后，Emacs 只需把 Termux 的 bin 目录加入 PATH（官方建议放在 `early-init.el`）：

```elisp
(when (string-equal system-type "android")
  (let ((termuxpath "/data/data/com.termux/files/usr/bin"))
    (setenv "PATH" (concat (getenv "PATH") ":" termuxpath))
    (setq exec-path (append exec-path (list termuxpath)))))
```

两个官方明确注意事项：

- **不要设置 `LD_LIBRARY_PATH`**。GNU 官方 README 明确指出旧 FAQ 的该建议是错误的——它会导致系统库与 Termux 库冲突。
- 若使用 F-Droid 版 Emacs（编译时无 GnuTLS 库支持），需在 Termux 内安装 `gnutls` 并改用 `gnutls-cli` 访问 HTTPS 站点（如 MELPA）：

  ```elisp
  (when (string-equal system-type "android")
    (setq tls-program '("gnutls-cli -p %p %h"
                        "gnutls-cli -p %p %h --protocols ssl3")))
  ```
