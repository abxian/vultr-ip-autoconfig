#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR=/usr/local/lib/vultr-ip-autoconfig
readonly SYNC_LINK=/usr/local/sbin/vultr-ip-sync
readonly ADD_LINK=/usr/local/sbin/vultr-ip-add
readonly CONFIG=/etc/vultr-ip-autoconfig.conf
readonly IP_LIST=/etc/vultr-extra-ipv4.list
readonly SERVICE=/etc/systemd/system/vultr-ip-autoconfig.service
readonly TIMER=/etc/systemd/system/vultr-ip-autoconfig.timer
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 sudo 运行：sudo ./install.sh"
command -v systemctl >/dev/null || die "当前系统不支持 systemd"

for command_name in ip flock; do
  command -v "$command_name" >/dev/null || missing="${missing:-} $command_name"
done
if [[ -n ${missing:-} ]]; then
  if command -v apt-get >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y iproute2 util-linux
  elif command -v dnf >/dev/null; then
    dnf install -y iproute util-linux
  elif command -v yum >/dev/null; then
    yum install -y iproute util-linux
  else
    die "缺少依赖:${missing}；请先安装"
  fi
fi

[[ -f "$SCRIPT_DIR/vultr-ip-sync.sh" ]] || die "找不到 vultr-ip-sync.sh"
[[ -f "$SCRIPT_DIR/vultr-ip-add.sh" ]] || die "找不到 vultr-ip-add.sh"

new_addresses="$*"
if [[ -z "$new_addresses" && -r /dev/tty ]]; then
  read -r -p '请输入新增公网 IPv4（多个用空格分隔）: ' new_addresses </dev/tty || true
fi
new_addresses=${new_addresses//,/ }
[[ -n "$new_addresses" ]] || die "至少需要输入一个新增 IPv4"

install -d -m 0755 "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/vultr-ip-sync.sh" "$INSTALL_DIR/vultr-ip-sync.sh"
install -m 0755 "$SCRIPT_DIR/vultr-ip-add.sh" "$INSTALL_DIR/vultr-ip-add.sh"
ln -sfn "$INSTALL_DIR/vultr-ip-sync.sh" "$SYNC_LINK"
ln -sfn "$INSTALL_DIR/vultr-ip-add.sh" "$ADD_LINK"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
[[ ! -e "$CONFIG" ]] || install -m 0600 "$CONFIG" "${CONFIG}.bak.${timestamp}"
[[ ! -e "$IP_LIST" ]] || install -m 0600 "$IP_LIST" "${IP_LIST}.bak.${timestamp}"
printf '%s\n' '# 留空时自动使用 IPv4 默认路由对应的网卡' 'INTERFACE=""' >"$CONFIG"
chmod 0600 "$CONFIG"
touch "$IP_LIST"
chmod 0600 "$IP_LIST"

cat >"$SERVICE" <<'EOF'
[Unit]
Description=Restore configured secondary IPv4 addresses
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vultr-ip-sync
User=root
Group=root
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_NETLINK AF_UNIX
ReadWritePaths=/run/lock

[Install]
WantedBy=multi-user.target
EOF

cat >"$TIMER" <<'EOF'
[Unit]
Description=Periodically restore configured secondary IPv4 addresses

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
RandomizedDelaySec=15s
Persistent=true

[Install]
WantedBy=timers.target
EOF

chmod 0644 "$SERVICE" "$TIMER"
systemctl daemon-reload

# Intentional word splitting: accepts a space-separated IP list.
# shellcheck disable=SC2086
"$ADD_LINK" $new_addresses
systemctl enable --now vultr-ip-autoconfig.timer

printf '\n安装完成。以后新增 IP：sudo vultr-ip-add 新IP\n'
printf '查看当前配置：ip -br -4 address\n'
