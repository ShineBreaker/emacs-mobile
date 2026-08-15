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

# ═══ emacs-mobile 配置依赖（字体 / 图标 / 插件预构建）═══

maple-font-url := "https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-NF-CN.zip"

# 一键补全配置侧依赖：字体 → 图标 → 插件预构建
deps: font icons packages

# 生成 tool-bar 图标（Maple NF 字形 → 56px PNG，随仓库分发；缺失才重建）。
# 桌面依赖 rsvg-convert（librsvg）与本机 Maple 字体；中灰填充双主题通吃。
icons:
    #!/usr/bin/env bash
    set -euo pipefail
    wanted="modbar save copy cut paste undo redo search recenter theme config dashboard"
    missing=""
    for n in $wanted; do [[ -f "data/icons/$n.png" ]] || missing="$missing $n"; done
    if [[ -z "$missing" ]]; then
        echo "data/icons/ 图标已齐（随仓库分发），跳过"
        exit 0
    fi
    command -v rsvg-convert >/dev/null || { echo "需要 rsvg-convert (librsvg)"; exit 1; }
    command -v fc-list >/dev/null || { echo "需要 fontconfig (fc-list)"; exit 1; }
    # 不用 grep -q：-q 命中即退出会让 fc-list 吃 EPIPE，pipefail 下误报
    fc-list :family | grep -i "maple" >/dev/null || { echo "先运行 just font 安装字体"; exit 1; }
    mkdir -p data/icons
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    # 图标规格：名字 | 码点 | 渲染字号。y=42 为 baseline 下移的光学居中
    # （dominant-baseline 在 librsvg 不可靠）。同时落 .svg 矢量资产
    # （真机验证 svg 渲染可用后可切 :type svg，见 PLAN §15）。
    spec=(
        "modbar &#xF11C; 40"   "save &#xF0C7; 40"    "copy &#xF0C5; 40"
        "cut &#xF0C4; 40"      "paste &#xF0EA; 40"   "undo &#xF0E2; 40"
        "redo &#xF01E; 40"     "search &#xF002; 40"  "recenter &#xF037; 40"
        "theme &#xF042; 40"    "config &#xF013; 40"  "dashboard &#xF021; 40"
    )
    for item in "${spec[@]}"; do
        read -r name glyph size <<<"$item"
        printf '%s\n' \
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"56\" height=\"56\"><text x=\"28\" y=\"42\" font-family=\"Maple Mono NF CN\" font-size=\"$size\" fill=\"#808080\" text-anchor=\"middle\">$glyph</text></svg>" \
            > "$tmp"
        rsvg-convert -w 56 -h 56 "$tmp" > "data/icons/$name.png"
        cp "$tmp" "data/icons/$name.svg"
    done
    echo "已生成 data/icons/{${wanted// /,}}.png + .svg"

# 下载 Maple Mono NF CN（中英等宽 + Nerd 图标）并安装。
# Android → Emacs home 的 fonts/（sfnt-android 枚举）；桌面 → fontconfig 用户目录。
# 安装后需重启 Emacs 生效。
font:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v fc-list >/dev/null && fc-list :family | grep -qi "maple"; then
        echo "Maple 字体已安装，跳过"
        exit 0
    fi
    command -v curl >/dev/null || { echo "需要 curl"; exit 1; }
    command -v unzip >/dev/null || { echo "需要 unzip"; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL --retry 3 --max-time 300 -o "$tmp/maple.zip" "{{maple-font-url}}"
    unzip -o -q "$tmp/maple.zip" -d "$tmp/font"
    if [[ -d /data/data/org.gnu.emacs ]]; then
        dest="/data/data/org.gnu.emacs/files/fonts"
    else
        dest="${HOME}/.local/share/fonts"
    fi
    mkdir -p "$dest"
    cp "$tmp"/font/MapleMono-NF-CN-Regular.ttf \
       "$tmp"/font/MapleMono-NF-CN-Italic.ttf \
       "$tmp"/font/MapleMono-NF-CN-Bold.ttf "$dest"/
    fc-cache -f >/dev/null 2>&1 || true
    echo "字体已安装到 $dest（重启 Emacs 生效）"

# 预构建全部 Emacs 插件（跑一遍完整 init，straight 装齐并 byte-compile）。
# 真机缓存 → ~/.cache/emacs/straight；桌面 → .sandbox/ 下（隔离）。
packages:
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(pwd)
    if [[ ! -d /data/data/org.gnu.emacs ]]; then
        export HOME="$here/.sandbox"
        mkdir -p "$HOME"
    fi
    emacs --batch \
        --eval "(setq user-emacs-directory \"$here/\")" \
        -l early-init.el -l init.el
    echo "全部插件已构建完成"
