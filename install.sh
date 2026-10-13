#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR=/usr/local/lib/vultr-ip-autoconfig
readonly BIN_LINK=/usr/local/sbin/vultr-ip-sync
readonly CONFIG=/etc/vultr-ip-autoconfig.conf
readonly SERVICE=/etc/systemd/system/vultr-ip-autoconfig.service
readonly TIMER=/etc/systemd/system/vultr-ip-autoconfig.timer
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 sudo 运行：sudo ./install.sh"
command -v systemctl >/dev/null || die "当前系统不支持 systemd"

for command_name in curl jq ip flock; do
  command -v "$command_name" >/dev/null || missing="${missing:-} $command_name"
done
if [[ -n ${missing:-} ]]; then
  if command -v apt-get >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq iproute2 util-linux
  elif command -v dnf >/dev/null; then
    dnf install -y curl jq iproute util-linux
  elif command -v yum >/dev/null; then
    yum install -y curl jq iproute util-linux
  else
    die "缺少依赖:${missing}；请先安装"
  fi
fi

[[ -f "$SCRIPT_DIR/vultr-ip-sync.sh" ]] || die "找不到 $SCRIPT_DIR/vultr-ip-sync.sh，请克隆完整仓库后运行"

if [[ -z ${VULTR_API_KEY:-} ]]; then
  [[ -r /dev/tty ]] || die "请通过环境变量 VULTR_API_KEY 提供 Token"
  read -r -s -p '请输入 Vultr API Token（输入不会显示）: ' VULTR_API_KEY </dev/tty
  printf '\n' >/dev/tty
fi
[[ -n "$VULTR_API_KEY" ]] || die "Vultr API Token 不能为空"

read -r -p '实例 ID（可留空自动识别）: ' INSTANCE_ID </dev/tty || true
read -r -p '同步间隔，systemd 格式 [默认 2min]: ' SYNC_INTERVAL </dev/tty || true
SYNC_INTERVAL=${SYNC_INTERVAL:-2min}

install -d -m 0755 "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/vultr-ip-sync.sh" "$INSTALL_DIR/vultr-ip-sync.sh"
ln -sfn "$INSTALL_DIR/vultr-ip-sync.sh" "$BIN_LINK"

umask 077
tmp_config=$(mktemp)
trap 'rm -f "$tmp_config"' EXIT
{
  printf 'VULTR_API_KEY=%q\n' "$VULTR_API_KEY"
  [[ -n ${INSTANCE_ID:-} ]] && printf 'INSTANCE_ID=%q\n' "$INSTANCE_ID"
  printf '# INTERFACE=enp1s0\n'
} >"$tmp_config"
if [[ -e "$CONFIG" ]]; then
  backup="${CONFIG}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  install -m 0600 "$CONFIG" "$backup"
  printf '原配置已备份到 %s\n' "$backup"
fi
install -m 0600 "$tmp_config" "$CONFIG"

cat >"$SERVICE" <<'EOF'
[Unit]
Description=Synchronize Vultr public secondary IPv4 addresses
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

cat >"$TIMER" <<EOF
[Unit]
Description=Periodically synchronize Vultr secondary IPv4 addresses

[Timer]
OnBootSec=1min
OnUnitActiveSec=$SYNC_INTERVAL
RandomizedDelaySec=15s
Persistent=true

[Install]
WantedBy=timers.target
EOF

chmod 0644 "$SERVICE" "$TIMER"
systemctl daemon-reload

printf '\n先执行只读预演：\n'
if ! "$BIN_LINK" --dry-run; then
  printf '\n预演失败，服务尚未启用。请检查 Token、API 白名单或填写 INSTANCE_ID。\n' >&2
  exit 1
fi

printf '\n预演成功，正在执行首次同步并启用定时器……\n'
systemctl start vultr-ip-autoconfig.service
systemctl enable --now vultr-ip-autoconfig.timer
systemctl --no-pager status vultr-ip-autoconfig.timer || true

printf '\n安装完成。查看日志：journalctl -u vultr-ip-autoconfig.service -n 50 --no-pager\n'
