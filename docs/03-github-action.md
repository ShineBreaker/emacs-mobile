# GitHub Action 自动重签使用说明

工作流 [.github/workflows/resign-termux.yml](../.github/workflows/resign-termux.yml) 自动完成：抓取 [termux/termux-app](https://github.com/termux/termux-app) 最新**预览版**（prerelease）APK → 按官方 sha256sums 校验 → 用仓库内 Emacs 构建密钥重签 → 核对证书指纹 → 发布为本仓库的 GitHub Release（标记 Pre-release）。

**无需配置任何 Secrets**：签名密钥是 Emacs 官方公开分发的（[assets/emacs.keystore](../assets/emacs.keystore)），发布使用内置 `GITHUB_TOKEN`（已声明 `contents: write` 权限）。

## 触发方式

### 定时自动（默认启用）

每天北京时间 02:30（`cron: "30 18 * * *"`）检查上游。若最新预览版的 tag 在本仓库已有同名 release，本次直接跳过，**不会重复发布**。上游没有新预览版时不产生任何变更。

不需要定时的话，删除 workflow 里 `schedule:` 那两行即可。

### 手动触发

Actions 页面 → _Resign Termux prerelease_ → _Run workflow_，可选参数：

| 参数   | 默认             | 说明                                                    |
| ------ | ---------------- | ------------------------------------------------------- |
| tag    | 空（最新预览版） | 指定上游 tag，如 `v0.119.0-beta.3`，可重发历史版本      |
| flavor | `apt-android-7`  | Android 7+ 用默认；Android 5/6 老设备用 `apt-android-5` |
| abi    | `universal`      | 全设备通用；也可 `arm64-v8a` 等                         |
| force  | false            | 同名 release 已存在时删除重建（含重新上传 APK）         |

## 产物

- Release tag 与上游一致（如 `v0.119.0-beta.3`），标题标注 _resigned for Emacs_
- APK 文件名为上游资产名加 `-emacs-signed` 后缀
- Release notes 含上游版本链接、原始资产名、证书指纹与安装顺序提醒

## 脚本的本地复用

推荐用 `just`（见仓库根 `justfile`），在 Guix 等自带 `curl` / `jq` / `unzip` / `java` 的环境开箱即用：

```sh
just tools    # 一次性准备 apksigner（下载 build-tools 34 并提取 jar，约 60MB）
just build    # 抓取 + 重签一条龙，产物在 download/*-emacs-signed.apk
just fetch    # 只抓取（可 just fetch tag=v0.119.0-beta.3 abi=arm64-v8a）
just resign   # 只重签（缺省自动选 download/ 下最新的未签名 APK）
just clean    # 清理 download/
```

重复 `just build` 不会重新下载：APK 已存在且官方 sha256 校验通过时自动跳过。已装 Android SDK 的系统可 `export APKSIGNER=apksigner` 覆盖默认的 jar 调用；依赖缺失的环境可在依赖齐全的容器中运行（如 `distrobox enter my-distrobox`）。

也可以直接用裸脚本：

```sh
# 抓最新预览版 universal APK 到 download/，自动做 sha256 校验
# stdout 输出 tag=... / asset=... / apk=... 三行（进度信息走 stderr）
scripts/fetch-termux-prerelease.sh -o download

# 指定版本与 ABI
scripts/fetch-termux-prerelease.sh -t v0.119.0-beta.3 -a arm64-v8a

# 重签（默认用仓库内密钥，输出 xxx-emacs-signed.apk 并断言证书指纹）
scripts/resign-apk.sh download/termux-app_*.apk

# 本地没有 Android SDK 时，直接指定 apksigner jar
APKSIGNER="java -jar /path/to/apksigner.jar" scripts/resign-apk.sh <apk>
```

脚本细节：`fetch-termux-prerelease.sh` 只访问 GitHub 官方域（URL 白名单校验，仅 https）；`resign-apk.sh` 签名后强制比对证书 SHA-256 指纹 `50b47e8f...96:04`，密钥文件异常会直接失败。

## 故障排查

| 现象                                     | 原因与处理                                                                                                      |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| 抓取步骤报 "release 列表获取失败" 或 403 | GitHub API 匿名限流。本地运行前 `export GITHUB_TOKEN=<token>`；CI 已自动传入                                    |
| 报 "没有预览版"                          | 上游最近 30 个 release 全是稳定版（脚本只认 prerelease 标记）                                                   |
| 报 "未匹配到 ... 的 APK 资产"            | 上游资产命名规则变化，或 flavor/abi 参数拼写错误                                                                |
| 定时任务没跑                             | 仓库超过 60 天无活动时 GitHub 会暂停 scheduled workflow，需手动到 Actions 页重新启用                            |
| 装机后 Emacs 仍找不到 git                | 检查是否按 [02-manual-resign.md](02-manual-resign.md) 第 5 节的顺序安装、Emacs 的 `early-init.el` 是否注入 PATH |
