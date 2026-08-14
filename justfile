# 本地命令包装。Guix 环境开箱即用（依赖 curl / jq / unzip / java）。
# 其他环境自装依赖后同样可用；已装 Android SDK 的系统可 export APKSIGNER=apksigner
# 覆盖默认的 jar 调用方式，或在依赖齐全的容器中运行，如:
#   distrobox enter my-distrobox

# apksigner 调用命令，默认用 `just tools` 准备的 build-tools jar
apksigner_cmd := env_var_or_default("APKSIGNER", "java -jar tools/apksigner.jar")

# 列出所有配方
default:
    @just --list

# 一次性准备 apksigner：下载 build-tools 34 并提取 apksigner.jar（临时下载约 60MB）
tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f tools/apksigner.jar ]]; then
        echo "tools/apksigner.jar 已存在，跳过"
        exit 0
    fi
    mkdir -p tools
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    url="https://dl.google.com/android/repository/build-tools_r34-linux.zip"
    echo "==> 下载 $url"
    curl -fsSL --retry 3 -o "$tmp/bt.zip" "$url"
    unzip -q "$tmp/bt.zip" 'android-14/lib/apksigner.jar' -d "$tmp"
    mv "$tmp/android-14/lib/apksigner.jar" tools/
    java -jar tools/apksigner.jar --version

# 抓取上游预览版 APK 到 download/ 并校验 sha256（本地已有且校验通过则跳过下载）
fetch tag="" flavor="apt-android-7" abi="universal":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(-o download -f "{{flavor}}" -a "{{abi}}")
    if [[ -n "{{tag}}" ]]; then args+=(-t "{{tag}}"); fi
    scripts/fetch-termux-prerelease.sh "${args[@]}"

# 用 Emacs 构建密钥重签 APK 并断言证书指纹（缺省自动选 download/ 下最新的未签名 APK）
resign apk="": tools
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{apk}}"
    if [[ -z "$target" ]]; then
        target=$(ls -t download/*.apk 2>/dev/null | grep -v 'emacs-signed' | sed -n '1p' || true)
        if [[ -z "$target" ]]; then
            echo "download/ 下没有待签名的 APK，先运行: just fetch" >&2
            exit 1
        fi
    fi
    APKSIGNER="{{apksigner_cmd}}" scripts/resign-apk.sh "$target"

# 抓取 + 重签一条龙（参数同 fetch；产物为 download/ 下 *-emacs-signed.apk）
build tag="" flavor="apt-android-7" abi="universal": tools
    #!/usr/bin/env bash
    set -euo pipefail
    args=(-o download -f "{{flavor}}" -a "{{abi}}")
    if [[ -n "{{tag}}" ]]; then args+=(-t "{{tag}}"); fi
    out=$(scripts/fetch-termux-prerelease.sh "${args[@]}")
    apk=$(sed -n 's/^apk=//p' <<<"$out")
    APKSIGNER="{{apksigner_cmd}}" scripts/resign-apk.sh "$apk"
    echo
    echo "==> 产物: ${apk%.apk}-emacs-signed.apk"

# 清理下载目录
clean:
    rm -rf download
