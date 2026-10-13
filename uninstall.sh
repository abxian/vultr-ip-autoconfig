#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo '请使用 sudo 运行' >&2; exit 1; }

systemctl disable --now vultr-ip-autoconfig.timer 2>/dev/null || true
systemctl stop vultr-ip-autoconfig.service 2>/dev/null || true
rm -f /etc/systemd/system/vultr-ip-autoconfig.service
rm -f /etc/systemd/system/vultr-ip-autoconfig.timer
rm -f /usr/local/sbin/vultr-ip-sync
rm -rf /usr/local/lib/vultr-ip-autoconfig
systemctl daemon-reload

echo '程序与 systemd 服务已删除。'
echo '出于安全考虑，配置文件 /etc/vultr-ip-autoconfig.conf 和已经添加的 IP 地址未删除。'
