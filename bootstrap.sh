#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY="abxian/vultr-ip-autoconfig"
readonly REVISION="main"
readonly INSTALL_SHA256="3c552b5e4c9797f83faf363d90549443de5a216ff3a3f6a9097bdbebea26227c"
readonly SYNC_SHA256="8af3df1659fbcd497fefe92a8f0a50a9b6c1d73b76a29a134c00fea93ea7f0c5"
readonly RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REVISION}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 sudo 运行"
command -v curl >/dev/null || die "缺少 curl"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
umask 077

download() {
  local name=$1
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --retry 3 --connect-timeout 10 --max-time 60 \
    "$RAW_BASE/$name" --output "$tmp_dir/$name"
}

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "缺少 sha256sum 或 shasum，无法校验下载内容"
  fi
}

download install.sh
download vultr-ip-sync.sh

[[ $(sha256 "$tmp_dir/install.sh") == "$INSTALL_SHA256" ]] || die "install.sh SHA-256 校验失败"
[[ $(sha256 "$tmp_dir/vultr-ip-sync.sh") == "$SYNC_SHA256" ]] || die "vultr-ip-sync.sh SHA-256 校验失败"

chmod 0700 "$tmp_dir/install.sh" "$tmp_dir/vultr-ip-sync.sh"
printf '下载和 SHA-256 校验通过，启动安装器……\n'
"$tmp_dir/install.sh"
