# Vultr IP Autoconfig

自动检测 Vultr 实例中新分配的公网 IPv4，并把系统里缺少的地址以 `/32` 添加到默认公网网卡。

## 安全设计

- 只添加 Vultr API 返回的公网非主 IPv4；不改默认路由、网关、DNS 或主 IP。
- 永不自动删除本机已有地址，API 故障不会造成 SSH 主地址被清理。
- 安装前强制执行 `--dry-run`；预演失败时不启用定时器。
- API Token 只写入服务器的 `/etc/vultr-ip-autoconfig.conf`，权限为 `0600`，不会上传 GitHub。
- 重复执行安全，systemd 定时器默认每两分钟同步一次。

## 前置条件

1. 在 Vultr 控制台把额外 IPv4 或 Reserved IP 附加到目标实例。
2. 创建一个 Vultr API Token。若账号启用了 API IP 白名单，请允许目标服务器的主 IP。
3. 建议先通过 Vultr Web Console 保留一个救援会话，并先轮换已经暴露过的 root 密码。

## 一键安装

在目标 Vultr 服务器执行：

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/abxian/vultr-ip-autoconfig/main/bootstrap.sh | sudo bash
```

引导脚本会从本仓库下载安装器和同步器，逐一核验固定的 SHA-256 后再执行。安装器会通过 `/dev/tty` 安全提示输入 Vultr API Token；Token 不会显示，也不会进入 shell 历史或进程参数。

### 克隆后安装

克隆仓库后运行：

```bash
sudo ./install.sh
```

实例 ID 可以留空，程序会用本机已有的主 IPv4 自动匹配 Vultr 实例。

不要使用下面这种形式传 Token，它会进入 shell 历史或进程环境：

```bash
# 不推荐
sudo ./install.sh --token "TOKEN"
```

## 手动预演和同步

```bash
sudo vultr-ip-sync --dry-run
sudo vultr-ip-sync
ip -br -4 address
```

验证某个新增 IP 的出站连接：

```bash
curl --interface 新增IP https://api.ipify.org
```

查看状态和日志：

```bash
systemctl status vultr-ip-autoconfig.timer
journalctl -u vultr-ip-autoconfig.service -n 50 --no-pager
```

## 配置

配置文件是 `/etc/vultr-ip-autoconfig.conf`：

```bash
VULTR_API_KEY='replace-me'
# 自动识别失败时填写：
# INSTANCE_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
# 默认路由不在公网网卡上时填写：
# INTERFACE='enp1s0'
```

修改后保持权限：

```bash
sudo chmod 600 /etc/vultr-ip-autoconfig.conf
```

## 卸载与回滚

```bash
sudo ./uninstall.sh
```

卸载默认保留配置文件以及已经加入网卡的 IP，避免意外中断正在使用的连接。确认不再需要后，可在 Vultr Web Console 中解绑地址，并通过控制台维护窗口手动删除对应的 `/32` 地址。

## 限制

- 当前版本只同步 IPv4。
- 程序只负责把 IP 加到网卡；Nginx、Docker、代理等服务是否监听该 IP，需要按应用单独配置。
- 若实例的默认路由使用其他接口，请在配置中明确指定 `INTERFACE`。

## 参考

- [Vultr：配置多个公网 IPv4](https://docs.vultr.com/how-to-configure-multiple-public-ipv4-addresses-on-a-vultr-compute-instance)
- [Vultr CLI：管理实例 IPv4](https://docs.vultr.com/reference/vultr-cli/instance/ipv4)

## License

MIT
