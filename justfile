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

# 生成 tool-bar 图标（Papirus symbolic 矢量，随仓库分发；缺失才重建）。
# SVG 直渲为主（Android 官方构建带 librsvg，矢量任意缩放），运行端按
# 主题重着色（替换 ColorScheme-Text 的 CSS 色，见 init-bar.el）。
# PNG 为 72px 2× 超采样兜底（中灰 #808080 双主题通吃）：无 librsvg 的
# 构建上 find-image 回退。桌面依赖 rsvg-convert；上游 GPL-3.0，
# 来源与许可见 data/icons/README.md。
papirus_tag := "20260801"
icons:
    #!/usr/bin/env bash
    set -euo pipefail
    base="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/{{papirus_tag}}/Papirus/24x24/symbolic"
    spec=(
        "modbar devices/input-keyboard"     "open actions/document-open"
        "save actions/document-save"        "copy actions/edit-copy"
        "paste actions/edit-paste"          "cut actions/edit-cut"
        "search actions/edit-find"          "theme status/night-light"
        "config places/folder"              "dashboard actions/view-grid"
    )
    missing=""
    for item in "${spec[@]}"; do
        read -r name _ <<<"$item"
        [[ -f "data/icons/$name.svg" ]] || missing="$missing $name"
    done
    # modifier-bar 徽章也算依赖（少了即触发重建）
    for n in control shift meta alt super hyper tab esc; do
        [[ -f "data/icons/mod-$n.pbm" ]] || missing="$missing mod-$n"
    done
    if [[ -z "$missing" ]]; then
        echo "data/icons/ 图标已齐（随仓库分发），跳过"
        exit 0
    fi
    command -v rsvg-convert >/dev/null || { echo "需要 rsvg-convert (librsvg)"; exit 1; }
    # 不用 grep -q：-q 命中即退出会让 fc-list 吃 EPIPE，pipefail 下误报
    command -v fc-list >/dev/null && fc-list :family | grep -i maple >/dev/null \
        || echo "提示：本机无 Maple 字体，徽章文字将用 fallback 字体渲染（建议先 just font）"
    mkdir -p data/icons
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # 仓库里多数 symbolic 图标是符号链接（raw URL 返回目标路径文本而非
    # SVG），须逐跳跟随解析到真实文件
    fetch_svg() {
        local url="$1" out="$2" content tries=0
        while :; do
            content=$(curl -fsSL --retry 3 "$url")
            [[ "$content" == \<* ]] && { printf '%s\n' "$content" > "$out"; return 0; }
            url="${url%/*}/$content"
            tries=$((tries + 1)); (( tries > 5 )) && return 1
        done
    }
    for item in "${spec[@]}"; do
        read -r name path <<<"$item"
        fetch_svg "$base/${path}-symbolic.svg" "$tmp/$name.svg"
        # 垂直防手势垫：画布统一 24×30、内容顶对齐（xMidYMin），底部留
        # 6 单位死区——:height 48 显示下约 10px，避开全面屏上滑手势区；
        # 横向不受影响。上游画布尺寸不一（22/24…），宽度高度都按通配替换
        sed -e 's/<svg \(.*\)width="[0-9]*" height="[0-9]*"/<svg \1width="24" height="30" preserveAspectRatio="xMidYMin"/' \
            "$tmp/$name.svg" > "$tmp/$name-pad.svg"
        # PNG 兜底：ColorScheme-Text 重着色中灰后 2× 光栅化（72×90）
        sed 's/\(ColorScheme-Text { color:\)#[0-9a-fA-F]*/\1#808080/' \
            "$tmp/$name-pad.svg" > "$tmp/$name-gray.svg"
        rsvg-convert -w 72 -h 90 "$tmp/$name-gray.svg" > "data/icons/$name.png"
        cp "$tmp/$name-pad.svg" "data/icons/$name.svg"
    done
    # modifier-bar 徽章：修饰键取前缀单字母（C S M A s H），Tab/Esc 全名。
    # 输出 PBM 位图（官方修饰键同机制，Android 真机验证可行；位图按
    # 工具栏前景色着色，深浅主题自动适配）。XPM 路线真机两次不渲染
    # （命名色/hex 色均败），弃；PNG alpha 在 Lucid 不合成露白底，仅作
    # PBM 不可用时的兜底。显示尺寸烤死在资产里：字母 28×28、
    # Tab/Esc 49×28（2× 渲染后 netpbm 缩小 + alpha 阈值化）。
    command -v pngtopam >/dev/null || { echo "需要 netpbm（guix install netpbm）"; exit 1; }
    mk_badge() {  # $1=name $2=label $3=canvasW $4=canvasH $5=outW $6=outH
        local name="$1" label="$2" cw="$3" ch="$4" ow="$5" oh="$6"
        local fs=$((ch*5/7))
        printf '%s\n' \
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$cw\" height=\"$ch\"><text x=\"$((cw/2))\" y=\"$((ch/2+fs*7/20))\" font-family=\"Maple Mono NF CN\" font-size=\"$fs\" fill=\"#000000\" text-anchor=\"middle\">$label</text></svg>" \
            > "$tmp/mod-$name.svg"
        rsvg-convert "$tmp/mod-$name.svg" > "$tmp/mod-$name.png"
        cp "$tmp/mod-$name.png" "data/icons/mod-$name.png"
        # PBM：alpha 通道阈值化（不透明=笔画），pnminvert 使笔画位=1
        # （PBM 1=黑=按前景色绘制的字形）
        pngtopam -alpha "$tmp/mod-$name.png" \
            | pamscale -xsize="$ow" -ysize="$oh" \
            | pgmtopbm -threshold | pnminvert > "data/icons/mod-$name.pbm"
    }
    mk_badge control  C   56 56 28 28
    mk_badge shift    S   56 56 28 28
    mk_badge meta     M   56 56 28 28
    mk_badge alt      A   56 56 28 28
    mk_badge super    s   56 56 28 28
    mk_badge hyper    H   56 56 28 28
    mk_badge tab      Tab 98 56 49 28
    mk_badge esc      Esc 98 56 49 28
    echo "已生成 10 枚 Papirus symbolic .svg + PNG 兜底 + 8 枚 modifier-bar 徽章（PBM）"

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
