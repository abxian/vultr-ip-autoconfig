#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROGRAM="vultr-ip-autoconfig"
CONFIG_FILE="${VULTR_IP_CONFIG:-/etc/vultr-ip-autoconfig.conf}"
API_BASE="${VULTR_API_BASE:-https://api.vultr.com/v2}"
DRY_RUN=false

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: vultr-ip-sync [--dry-run] [--config PATH]

Adds public secondary IPv4 addresses assigned to this Vultr instance but
missing from its main network interface. Existing addresses are never removed.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --config) shift; (($#)) || die "--config requires a path"; CONFIG_FILE="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"
[[ -r "$CONFIG_FILE" ]] || die "cannot read $CONFIG_FILE"

# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${VULTR_API_KEY:?VULTR_API_KEY is required in $CONFIG_FILE}"

command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required"
command -v ip >/dev/null || die "iproute2 is required"

exec 9>"${LOCK_FILE:-/run/lock/vultr-ip-autoconfig.lock}"
flock -n 9 || { log "another sync is already running"; exit 0; }

api_get() {
  local path=$1 body http error output
  body=$(mktemp)
  # Feed the authorization header over stdin instead of putting the token in
  # curl's argv, where another local user could briefly observe it with ps.
  http=$(
    printf 'header = "Authorization: Bearer %s"\n' "$VULTR_API_KEY" |
      curl --config - --silent --show-error --location \
    --connect-timeout 10 --max-time 30 \
    --output "$body" --write-out '%{http_code}' \
    --header 'Accept: application/json' \
    "${API_BASE}${path}"
  ) || die "Vultr API request failed: $path"
  if [[ "$http" != 200 ]]; then
    error=$(jq -r '.error // "unknown error"' "$body" 2>/dev/null || true)
    rm -f "$body"
    die "Vultr API returned HTTP $http for $path: ${error:-unknown error}"
  fi
  output=$(cat "$body")
  rm -f "$body"
  printf '%s\n' "$output"
}

is_ipv4() {
  local ip=$1 octet
  local -a octets
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$ip"
  for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
}

detect_interface() {
  if [[ -n ${INTERFACE:-} ]]; then
    ip link show dev "$INTERFACE" >/dev/null 2>&1 || die "configured interface does not exist: $INTERFACE"
    printf '%s\n' "$INTERFACE"
    return
  fi
  ip -4 route show default | awk 'NR == 1 {print $5}'
}

detect_instance_id() {
  if [[ -n ${INSTANCE_ID:-} ]]; then
    printf '%s\n' "$INSTANCE_ID"
    return
  fi

  local instances id
  instances=$(api_get '/instances?per_page=500')
  while IFS= read -r local_ip; do
    id=$(jq -r --arg ip "$local_ip" '.instances[] | select(.main_ip == $ip) | .id' <<<"$instances" | head -n1)
    if [[ -n "$id" ]]; then
      printf '%s\n' "$id"
      return
    fi
  done < <(ip -o -4 address show scope global | awk '{split($4,a,"/"); print a[1]}')

  die "could not identify this instance; set INSTANCE_ID in $CONFIG_FILE"
}

iface=$(detect_interface)
[[ -n "$iface" ]] || die "could not detect the default IPv4 interface; set INTERFACE in $CONFIG_FILE"
instance_id=$(detect_instance_id)
[[ "$instance_id" =~ ^[0-9a-fA-F-]{16,}$ ]] || die "invalid INSTANCE_ID returned: $instance_id"

addresses_json=$(api_get "/instances/${instance_id}/ipv4?per_page=500")
mapfile -t desired_ips < <(
  jq -r '.ipv4s[] | select(.type != "main_ip" and .type != "private") | .ip' <<<"$addresses_json" | sort -u
)

if ((${#desired_ips[@]} == 0)); then
  log "no public secondary IPv4 addresses assigned; nothing to do"
  exit 0
fi

changed=0
for address in "${desired_ips[@]}"; do
  is_ipv4 "$address" || die "API returned an invalid IPv4 address: $address"
  if ip -o -4 address show dev "$iface" | awk '{print $4}' | grep -Fxq "$address/32"; then
    log "already configured: $address/32 on $iface"
    continue
  fi

  if $DRY_RUN; then
    log "DRY-RUN: would add $address/32 to $iface"
  else
    ip address add "$address/32" dev "$iface"
    if command -v arping >/dev/null 2>&1; then
      arping -q -c 2 -U -I "$iface" "$address" || true
    fi
    log "added $address/32 to $iface"
  fi
  changed=$((changed + 1))
done

log "sync complete: instance=$instance_id interface=$iface assigned=${#desired_ips[@]} changed=$changed dry_run=$DRY_RUN"
