# 自由档案馆 | iwantrun.com 一键多协议VPN安装脚本

基于 **sing-box** 的一键多协议 VPN / 代理节点安装脚本。

适合部署在小型 VPS 上，支持一键安装、节点管理、二维码生成、用户管理和 sing-box 内核更新。

> 项目致谢：张狗剩同志 https://x.com/goshenggo  
> 更多 VPN 教程：https://iwantrun.com/category/vpn-proxy

---

## 📖 项目理念

在一个信息被高墙阻隔、真相被选择性遮蔽的时代，工具本身也可以成为一种微小但具体的抵抗。

所谓的“境外势力”，不应成为人们获取信息的恐惧来源；  
所谓的“盛世繁华”，也不应以封锁知识、限制言论为代价。

让更多被困在信息茧房中的人，拥有接触真实世界的可能。

---

## 🖼️ 演示图

### 主菜单演示

![自由档案馆一键多协议VPN脚本演示图](https://github.com/user-attachments/assets/7db67364-917d-494f-99f5-a1b6ee6245b0)

### 安装演示

![安装演示图](https://github.com/user-attachments/assets/c11652fe-6255-4e51-aef2-d43c64135616)

---

## 🚀 支持协议

- VLESS + REALITY + Vision
- Hysteria2
- AnyTLS
- VLESS + gRPC + REALITY
- TUIC

---

## ✨ 项目特色

- **一键安装**：中文菜单，新手也能使用
- **多协议支持**：一个脚本支持 5 种协议
- **基于 sing-box**：统一核心，方便管理和更新
- **随机端口**：自动生成端口，也支持手动自定义
- **二维码输出**：安装完成后自动显示节点链接和二维码
- **用户管理**：支持增加用户、删除用户、查看用户
- **适合小型 VPS**：体积小，依赖少，适合个人节点和备用节点
- **统一服务管理**：所有协议统一由 `sing-box.service` 管理

---

## 🖥️ 推荐系统

推荐使用：

```text
Ubuntu 22.04 LTS
```

也支持：

```text
Debian / CentOS / Rocky Linux / AlmaLinux
```

如果你是新手，建议优先选择 **Ubuntu 22.04**。

---

## ☁️ VPS 推荐

本脚本适合部署在常见小型 VPS 上，例如：

- Vultr
- Linode
- Hetzner
- DigitalOcean
- Oracle Cloud
- AWS Lightsail
- Google Cloud

推荐最低配置：

```text
CPU：1 核
内存：512MB 以上
硬盘：5GB 以上
系统：Ubuntu 22.04 / Ubuntu 24.04
```

个人使用或备用节点，小型 VPS 通常已经够用。

---

## 🔐 使用前准备：登录 VPS

运行脚本前，需要先通过 SSH 登录 VPS。

VPS 服务商通常会提供：

```text
服务器 IP
用户名
密码 或 SSH 密钥
```

---

## 🪟 Windows 用户 SSH 工具

Windows 10 / Windows 11 推荐使用：

- Windows Terminal
- PowerShell
- PuTTY
- Xshell

打开 Windows Terminal 或 PowerShell 后输入：

```bash
ssh root@你的服务器IP
```

---

## 🍎 macOS 用户 SSH 工具

macOS 自带 SSH 工具。

打开：

```text
终端 Terminal
```

然后输入：

```bash
ssh root@你的服务器IP
```

或者：

```bash
ssh ubuntu@你的服务器IP
```

---

## ⚙️ 安装命令

下面提供两种安装方式：`wget` 和 `curl`。

**只需要选择其中一种执行，不需要两条都执行。**

如果你的系统支持 `wget`，推荐使用第一种。  
如果提示 `wget: command not found`，再使用第二种 `curl` 命令。

### 方式一：使用 wget 安装

```bash
wget -O vpn.sh https://raw.githubusercontent.com/iwantruncom/multi-protocol-vpn/main/vpn.sh && chmod +x vpn.sh && sudo bash vpn.sh
```

### 方式二：使用 curl 安装

```bash
curl -L -o vpn.sh https://raw.githubusercontent.com/iwantruncom/multi-protocol-vpn/main/vpn.sh && chmod +x vpn.sh && sudo bash vpn.sh
```

---

## 📋 菜单功能

运行脚本后，会看到主菜单：

```text
1. 安装 / 重装协议
2. 管理当前服务
3. 用户管理
4. 查看当前节点链接
5. 卸载
0. 退出
```

---

## 🧩 协议介绍

| 选项 | 协议 | 工作原理 | 防封级别 | 推荐指数 |
|---|---|---|---|---|
| 1 | VLESS + REALITY + Vision | 模拟正常 HTTPS/TLS 连接，不需要域名和证书 | ★★★★★ | ★★★★★ |
| 2 | Hysteria2 | 基于 QUIC/UDP，偏高速和抗丢包 | ★★★★☆ | ★★★★☆ |
| 3 | AnyTLS | 新型 TLS 方向协议，接近普通 TLS 流量 | ★★★★☆ | ★★★☆☆ |
| 4 | VLESS + gRPC + REALITY | VLESS Reality + gRPC 传输方式 | ★★★★☆ | ★★★☆☆ |
| 5 | TUIC | 基于 QUIC/UDP，偏低延迟和高速 | ★★★★☆ | ★★★★☆ |

---

## 🔥 防火墙提醒

安装完成后，脚本会提示需要放行的端口，例如：

```text
手动放行当前端口：12345/TCP
```

请到 VPS 后台防火墙 / 安全组里手动放行对应端口。

如果端口没有放行，客户端可能无法连接。

常见需要检查的防火墙：

- Vultr Firewall
- Linode Firewall
- Hetzner Firewall
- DigitalOcean Firewall
- AWS Security Group
- Google Cloud Firewall
- Oracle Cloud Security List

脚本可以尝试放行系统内部防火墙，但 **VPS 后台防火墙 / 安全组仍然需要手动检查**。

---

## ❓ 常见问题

### 1. 安装成功后为什么连不上？

优先检查 VPS 后台防火墙 / 安全组是否放行了脚本提示的端口。

例如：

```text
手动放行当前端口：12345/TCP
```

### 2. 是否需要域名？

默认不需要域名。

本脚本目前集成的协议可以免域名部署。

### 3. 是否需要证书？

不需要手动申请证书。

脚本会根据不同协议自动处理相关配置。

### 4. 如何查看节点二维码？

运行脚本后选择：

```text
4. 查看当前节点链接
```

脚本会显示节点链接和二维码。

### 5. 如何增加用户？

运行脚本后选择：

```text
3. 用户管理
```

然后选择：

```text
2. 增加用户
```

### 6. 如何重启服务？

运行脚本后选择：

```text
2. 管理当前服务
```

然后选择：

```text
3. 重启 sing-box
```

也可以手动执行：

```bash
systemctl restart sing-box
```

### 7. 如何查看日志？

运行脚本后选择：

```text
2. 管理当前服务
```

然后选择：

```text
5. 查看实时日志
```

也可以手动执行：

```bash
journalctl -u sing-box -f --no-pager
```

### 8. 如何更新 sing-box 内核？

运行脚本后选择：

```text
2. 管理当前服务
```

然后选择：

```text
6. 更新 sing-box 内核
```

脚本会先备份当前配置，再更新 sing-box。

### 9. 如何卸载？

运行脚本后选择：

```text
5. 卸载
```

确认后会删除 sing-box、配置文件和 systemd 服务。

---

## 📁 常用文件位置

```text
sing-box 程序：
/usr/local/bin/sing-box

sing-box 配置：
/etc/sing-box/config.json

脚本管理信息：
/etc/freedom-vpn/info.json

systemd 服务：
/etc/systemd/system/sing-box.service
```

---

## 🛠️ 手动常用命令

查看服务状态：

```bash
systemctl status sing-box
```

重启服务：

```bash
systemctl restart sing-box
```

停止服务：

```bash
systemctl stop sing-box
```

查看日志：

```bash
journalctl -u sing-box -f --no-pager
```

检查配置：

```bash
sing-box check -c /etc/sing-box/config.json
```

---

## 🙏 致谢

特别感谢张狗剩同志：

https://x.com/goshenggo

没有张狗剩同志，就没有这个项目。

更多 VPN 教程：

https://iwantrun.com/category/vpn-proxy

---

## 📄 License

MIT License
