#!/usr/bin/env bash
# 抓取 termux/termux-app 预览版（prerelease）Release 的 APK，并按官方 sha256sums 校验。
#
# 用法:
#   fetch-termux-prerelease.sh [-o <下载目录>] [-f <flavor>] [-a <abi>] [-t <tag>] [-c]
#
# 选项:
#   -o  下载目录（默认: ./download）
#   -f  flavor，apt-android-7（默认，Android 7+）或 apt-android-5（Android 5/6）
#   -a  ABI，universal（默认）/ arm64-v8a / armeabi-v7a / x86_64 / x86
#   -t  指定上游 tag（如 v0.119.0-beta.3）；缺省取最新预览版
#   -c  check-only：只解析 tag/asset 并输出，不下载（用于先查已发布再决定是否下载）
#
# 输出（同时写入 $GITHUB_OUTPUT 供 workflow 使用）:
#   tag=<上游 tag>
#   asset=<上游资产名>
#   apk=<下载后的 APK 路径>（-c 模式不输出）
set -euo pipefail

die() { echo "错误: $*" >&2; exit 1; }

write_output() { echo "$1=$2"; [[ -n ${GITHUB_OUTPUT:-} ]] && echo "$1=$2" >>"$GITHUB_OUTPUT" || true; }

# 仅允许 https + GitHub 官方域，拒绝其余 host
validate_url() {
  case "$1" in
    https://api.github.com/* | https://github.com/* | https://objects.githubusercontent.com/*) ;;
    *) die "拒绝访问白名单之外的 URL: $1" ;;
  esac
}

OUT_DIR=download
FLAVOR=apt-android-7
ABI=universal
TAG_OPT=""
CHECK_ONLY=0

while getopts ":o:f:a:t:ch" opt; do
  case $opt in
    o) OUT_DIR=$OPTARG ;;
    f) FLAVOR=$OPTARG ;;
    a) ABI=$OPTARG ;;
    t) TAG_OPT=$OPTARG ;;
    c) CHECK_ONLY=1 ;;
    h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知选项，运行 $0 -h 查看用法" ;;
  esac
done

command -v curl >/dev/null || die "需要 curl"
command -v jq >/dev/null || die "需要 jq"

API="https://api.github.com/repos/termux/termux-app/releases?per_page=30"
validate_url "$API"

CURL_ARGS=(-fsSL --retry 3 --max-time 60)
if [[ -n ${GITHUB_TOKEN:-} ]]; then
  CURL_ARGS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

releases_json=$(curl "${CURL_ARGS[@]}" "$API") || die "获取 release 列表失败"
[[ -n $releases_json ]] || die "release 列表为空"

if [[ -n $TAG_OPT ]]; then
  release_json=$(jq --arg t "$TAG_OPT" '.[] | select(.tag_name == $t)' <<<"$releases_json")
  [[ -n $release_json ]] || die "上游不存在 tag 为 $TAG_OPT 的 release"
else
  release_json=$(jq '[.[] | select(.prerelease)][0]' <<<"$releases_json")
  [[ $release_json != null ]] || die "termux/termux-app 最近 30 个 release 中没有预览版"
fi

TAG=$(jq -r '.tag_name' <<<"$release_json")
# 资产命名: termux-app_<tag>+<flavor>-<buildtype>_<abi>.apk，buildtype 不限定
ASSET_PATTERN="^termux-app_.+\\+${FLAVOR}-.+_${ABI}\\.apk$"

ASSET=$(jq -r --arg p "$ASSET_PATTERN" '[.assets[] | select(.name | test($p)) | .name][0]' <<<"$release_json")
[[ -n $ASSET ]] || die "release $TAG 中未匹配到 flavor=$FLAVOR abi=$ABI 的 APK 资产"
APK_URL=$(jq -r --arg n "$ASSET" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$release_json")

if [[ $CHECK_ONLY -eq 1 ]]; then
  write_output tag "$TAG"
  write_output asset "$ASSET"
  echo "check-only 模式：最新预览版 $TAG（$ASSET），未下载" >&2
  exit 0
fi

mkdir -p "$OUT_DIR"
APK_PATH=$(cd "$OUT_DIR" && pwd)/$ASSET

# 官方 sha256sums 资产名与 APK 仅后缀不同: ..._<abi>.apk -> ..._sha256sums
SUMS_ASSET=${ASSET%_${ABI}.apk}_sha256sums
SUMS_URL=$(jq -r --arg n "$SUMS_ASSET" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$release_json")
expected=""
if [[ -n $SUMS_URL && $SUMS_URL != null ]]; then
  validate_url "$SUMS_URL"
  sums_file=$(mktemp)
  curl "${CURL_ARGS[@]}" -o "$sums_file" "$SUMS_URL" || die "下载 $SUMS_ASSET 失败"
  expected=$(awk -v asset="$ASSET" '$2 == asset {print $1}' "$sums_file")
  rm -f "$sums_file"
  [[ -n $expected ]] || die "sha256sums 中找不到 $ASSET 的条目"
fi

# 幂等：本地已有同名文件且 sha256 匹配则跳过下载
actual=""
if [[ -f $APK_PATH ]]; then
  actual=$(sha256sum "$APK_PATH" | awk '{print $1}')
fi
if [[ -n $expected && $actual == "$expected" ]]; then
  echo "$ASSET 已存在且 sha256 校验通过，跳过下载" >&2
else
  validate_url "$APK_URL"
  curl "${CURL_ARGS[@]}" -o "$APK_PATH" "$APK_URL" || die "下载 $ASSET 失败"
  [[ $(stat -c%s "$APK_PATH") -gt 1048576 ]] || die "下载的 APK 小于 1MB，疑似不完整"
fi

if [[ -n $expected ]]; then
  actual=$(sha256sum "$APK_PATH" | awk '{print $1}')
  [[ $actual == "$expected" ]] || die "sha256 校验失败: 期望 $expected 实际 $actual"
  echo "sha256 校验通过: $actual" >&2
else
  echo "警告: release $TAG 无 $SUMS_ASSET 资产，跳过校验" >&2
fi

write_output tag "$TAG"
write_output asset "$ASSET"
write_output apk "$APK_PATH"
