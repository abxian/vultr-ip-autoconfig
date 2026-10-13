#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${VULTR_IP_CONFIG:-/etc/vultr-ip-autoconfig.conf}"
IP_LIST_FILE="${VULTR_IP_LIST:-/etc/vultr-extra-ipv4.list}"
DRY_RUN=false

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      echo 'Usage: vultr-ip-sync [--dry-run]'
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"
command -v ip >/dev/null || die "iproute2 is required"
command -v flock >/dev/null || die "flock is required"

INTERFACE=""
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi
if [[ -z "$INTERFACE" ]]; then
  INTERFACE=$(ip -4 route show default | awk 'NR == 1 {print $5}')
fi
[[ -n "$INTERFACE" ]] || die "cannot detect the default IPv4 interface; set INTERFACE in $CONFIG_FILE"
ip link show dev "$INTERFACE" >/dev/null 2>&1 || die "interface does not exist: $INTERFACE"

exec 9>"${LOCK_FILE:-/run/lock/vultr-ip-autoconfig.lock}"
flock -n 9 || { log "another sync is already running"; exit 0; }

is_ipv4() {
  local address=$1 octet
  local -a octets
  [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$address"
  for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
}

[[ -r "$IP_LIST_FILE" ]] || { log "no IP list at $IP_LIST_FILE; nothing to do"; exit 0; }

changed=0
total=0
while IFS= read -r address || [[ -n "$address" ]]; do
  address=${address%%#*}
  address=${address//[[:space:]]/}
  [[ -z "$address" ]] && continue
  is_ipv4 "$address" || die "invalid IPv4 in $IP_LIST_FILE: $address"
  total=$((total + 1))

  if ip -o -4 address show dev "$INTERFACE" | awk '{split($4,a,"/"); print a[1]}' | grep -Fxq "$address"; then
    log "already configured: $address on $INTERFACE"
    continue
  fi

  if $DRY_RUN; then
    log "DRY-RUN: would add $address/32 to $INTERFACE"
  else
    ip address add "$address/32" dev "$INTERFACE"
    if command -v arping >/dev/null 2>&1; then
      arping -q -c 2 -U -I "$INTERFACE" "$address" || true
    fi
    log "added $address/32 to $INTERFACE"
  fi
  changed=$((changed + 1))
done <"$IP_LIST_FILE"

log "sync complete: interface=$INTERFACE listed=$total changed=$changed dry_run=$DRY_RUN"
