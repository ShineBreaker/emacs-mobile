#!/usr/bin/env bash
# 用 GNU Emacs 官方公开构建密钥（assets/emacs.keystore）重签 Termux APK，
# 使其与 Android 原生 Emacs（org.gnu.emacs）共享同一 UID。
# 签名命令与 Emacs 源码 java/Makefile.in 的 SIGN_EMACS_V2 一致；
# 该密钥由 Emacs 官方公开分发，storepass/keypass 均为 emacs1，无保密性。
#
# 用法:
#   resign-apk.sh <input.apk> [-o <output.apk>] [-k <keystore>]
#
# 选项:
#   -o  输出 APK（默认: <输入名去 .apk>-emacs-signed.apk）
#   -k  密钥库（默认: 仓库内 assets/emacs.keystore）
#
# 环境变量:
#   APKSIGNER  apksigner 命令（默认: apksigner；
#              本地无 SDK 时可用: APKSIGNER="java -jar /path/to/apksigner.jar"）
#
# 输出（同时写入 $GITHUB_OUTPUT 供 workflow 使用）:
#   apk=<重签后的 APK 路径>
set -euo pipefail

die() { echo "错误: $*" >&2; exit 1; }

# Emacs 构建密钥证书的 SHA-256 指纹，签名后强制比对，防止密钥文件被调包
EXPECTED_CERT_SHA256=50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEYSTORE=$REPO_ROOT/assets/emacs.keystore
APKSIGNER=${APKSIGNER:-apksigner}
OUT=""

[[ $# -ge 1 ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
INPUT=$1
shift

while getopts ":o:k:h" opt; do
  case $opt in
    o) OUT=$OPTARG ;;
    k) KEYSTORE=$OPTARG ;;
    h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知选项，运行 $0 -h 查看用法" ;;
  esac
done
[[ -f $INPUT ]] || die "输入 APK 不存在: $INPUT"
[[ -f $KEYSTORE ]] || die "密钥库不存在: $KEYSTORE"
[[ -n $OUT ]] || OUT=${INPUT%.apk}-emacs-signed.apk

read -r -a SIGNER_CMD <<<"$APKSIGNER"
command -v "${SIGNER_CMD[0]}" >/dev/null || die "找不到 apksigner（可通过 APKSIGNER 环境变量指定）"

echo "==> 重签 $INPUT"
"${SIGNER_CMD[@]}" sign --v2-signing-enabled \
  --ks "$KEYSTORE" -debuggable-apk-permitted \
  --ks-pass pass:emacs1 \
  --out "$OUT" "$INPUT"

digest=$("${SIGNER_CMD[@]}" verify --print-certs "$OUT" |
  sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
[[ $digest == "$EXPECTED_CERT_SHA256" ]] ||
  die "签名证书指纹与预期不符: $digest"
echo "==> 签名完成，证书指纹校验通过: $digest"
echo "apk=$OUT"
[[ -n ${GITHUB_OUTPUT:-} ]] && echo "apk=$OUT" >>"$GITHUB_OUTPUT" || true
