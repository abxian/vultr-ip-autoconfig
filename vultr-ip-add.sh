#!/usr/bin/env bash
set -Eeuo pipefail

readonly IP_LIST_FILE="${VULTR_IP_LIST:-/etc/vultr-extra-ipv4.list}"
readonly SYNC_COMMAND="${VULTR_IP_SYNC_COMMAND:-/usr/local/sbin/vultr-ip-sync}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 sudo 运行"
(($#)) || die "用法：sudo vultr-ip-add 新增IPv4 [更多IPv4...]"

is_ipv4() {
  local address=$1 octet
  local -a octets
  [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$address"
  for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
}

for address in "$@"; do is_ipv4 "$address" || die "无效 IPv4：$address"; done

tmp=$(mktemp "${IP_LIST_FILE}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
chmod 0600 "$tmp"
if [[ -r "$IP_LIST_FILE" ]]; then
  grep -Ev '^[[:space:]]*(#|$)' "$IP_LIST_FILE" >>"$tmp" || true
fi
printf '%s\n' "$@" >>"$tmp"
sort -u "$tmp" -o "$tmp"
install -m 0600 "$tmp" "$IP_LIST_FILE"

"$SYNC_COMMAND" --dry-run
"$SYNC_COMMAND"
printf '已保存并配置：%s\n' "$*"
