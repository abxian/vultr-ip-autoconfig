# Vultr IP Autoconfig

无需 Vultr API 或 Token。脚本自动识别 Linux 的 IPv4 默认网卡，把你输入的额外公网 IPv4 以 `/32` 加入网卡，并在重启后自动恢复。

服务器无法获知“Vultr 控制台已分配、但操作系统尚未配置”的未知 IP，因此每个新增 IP 首次需要输入一次；系统、网卡和持久化配置均自动处理。

## 一键安装

交互输入新增 IP：

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/abxian/vultr-ip-autoconfig/main/bootstrap.sh | sudo bash
```

也可以在命令末尾直接提供一个或多个 IP：

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/abxian/vultr-ip-autoconfig/main/bootstrap.sh | sudo bash -s -- 203.0.113.10 203.0.113.11
```

引导脚本会核验下载文件的 SHA-256 后再运行。

## 以后新增 IP

```bash
sudo vultr-ip-add 203.0.113.12
sudo vultr-ip-add 203.0.113.13 203.0.113.14
```

## 工作方式

- 自动从 IPv4 默认路由识别公网网卡。
- 新增 IP 使用 `/32`，不修改主 IP、默认路由、网关或 DNS。
- 地址保存在 `/etc/vultr-extra-ipv4.list`，权限为 `0600`。
- systemd 在开机后以及每两分钟检查一次，缺少时自动恢复。
- 只添加、不自动删除地址，避免误断 SSH。

## 验证

```bash
ip -br -4 address
sudo vultr-ip-sync --dry-run
curl --interface 新增IP https://api.ipify.org
journalctl -u vultr-ip-autoconfig.service -n 50 --no-pager
```

## 指定网卡

默认路由不在公网网卡时，编辑 `/etc/vultr-ip-autoconfig.conf`：

```bash
INTERFACE="enp1s0"
```

然后执行 `sudo vultr-ip-sync`。

## 卸载

克隆仓库后执行 `sudo ./uninstall.sh`。卸载默认保留 IP 清单和当前网卡地址，避免意外中断连接。

## 安全说明

- 不需要 Vultr API Key。
- 请先在 Vultr 控制台确认输入的 IP 确实属于目标实例。
- 脚本不包含服务器地址或登录凭据。

## License

MIT
