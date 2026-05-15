#!/bin/bash

# ========================================================
# 自由档案馆 | iwantrun.com 一键多协议VPN脚本 v1.1
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_VERSION="v1.1"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="/etc/sing-box/config.json"
INFO_DIR="/etc/freedom-vpn"
INFO_FILE="/etc/freedom-vpn/info.json"
SB_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"

pause(){ echo; read -rp "按回车返回菜单..."; }
die(){ echo -e "${RED}错误：$1${NC}"; exit 1; }

print_header(){
    clear
    echo -e "${CYAN}=================================================================${NC}"
    echo -e "${GREEN}      自由档案馆 | iwantrun.com 一键多协议VPN脚本 ${APP_VERSION}${NC}"
    echo -e "${GREEN}      支持协议: VLESS / Hysteria2 / AnyTLS / gRPC Reality / TUIC${NC}"
    echo -e "${GREEN}      项目致谢: 没有张狗剩同志 (https://x.com/goshenggo), 就没有这个项目${NC}"
    echo -e "${GREEN}      更多VPN教程, 请访问: https://iwantrun.com/category/vpn-proxy${NC}"
    echo -e "${CYAN}=================================================================${NC}"
}

urlencode(){
    local string="$1" strlen=${#1} encoded="" pos c o
    for ((pos=0; pos<strlen; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) o="$c" ;;
            *) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

check_root(){ [[ "$EUID" -ne 0 ]] && die "请使用 root 用户运行此脚本。"; }

detect_arch(){
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) die "暂不支持当前架构：$(uname -m)" ;;
    esac
}

install_dependencies(){
    echo -e "${YELLOW}正在安装基础依赖...${NC}"

    if command -v apt >/dev/null 2>&1; then
        apt update -y >/dev/null 2>&1
        apt install -y curl wget jq openssl tar unzip python3 python3-pip ca-certificates iproute2 >/dev/null 2>&1 || die "apt 安装依赖失败，请先手动运行 apt update 检查错误。"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl wget jq openssl tar unzip python3 python3-pip ca-certificates iproute >/dev/null 2>&1 || die "dnf 安装依赖失败。"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl wget jq openssl tar unzip python3 python3-pip ca-certificates iproute >/dev/null 2>&1 || die "yum 安装依赖失败。"
    else
        die "暂不支持此系统。请使用 Debian / Ubuntu / CentOS / Rocky / AlmaLinux。"
    fi

    pip3 install qrcode[pil] --break-system-packages >/dev/null 2>&1 || pip3 install qrcode[pil] >/dev/null 2>&1 || true
}

enable_bbr(){
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        echo -e "${GREEN}BBR 已开启。${NC}"
        return
    fi

    echo -e "${YELLOW}正在尝试开启 BBR...${NC}"

    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf 2>/dev/null || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
}

get_public_ip(){
    local ip
    ip=$(curl -s4 --max-time 8 https://api.ipify.org || true)
    [[ -z "$ip" ]] && ip=$(curl -s4 --max-time 8 https://icanhazip.com || true)
    ip=$(echo "$ip" | tr -d '[:space:]')
    [[ -z "$ip" ]] && die "无法获取服务器公网 IPv4。"
    echo "$ip"
}

generate_random_port(){
    local p
    while true; do
        p=$(shuf -i 10000-60000 -n 1)
        if ! ss -lntup 2>/dev/null | grep -q ":${p}\b"; then
            echo "$p"
            return
        fi
    done
}

choose_port(){
    local random_port custom_port
    random_port=$(generate_random_port)

    echo -e "\n${YELLOW}系统已为当前协议随机生成端口：${CYAN}${random_port}${NC}"
    read -rp "如果你想自定义端口，请输入端口号；直接回车使用随机端口: " custom_port

    if [[ -n "$custom_port" ]]; then
        [[ "$custom_port" =~ ^[0-9]+$ ]] || die "端口必须是数字。"
        (( custom_port >= 1 && custom_port <= 65535 )) || die "端口范围必须是 1-65535。"
        PORT="$custom_port"
    else
        PORT="$random_port"
    fi

    if ss -lntup 2>/dev/null | grep -q ":${PORT}\b"; then
        echo -e "${RED}端口 ${PORT} 已被占用：${NC}"
        ss -lntup 2>/dev/null | grep ":${PORT}\b" || true
        exit 1
    fi

    echo -e "${GREEN}当前协议将使用端口：${PORT}${NC}"
}

open_firewall_port(){
    local protocol_type="$1"

    echo -e "${YELLOW}正在尝试放行系统防火墙端口...${NC}"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
        [[ "$protocol_type" == "udp" || "$protocol_type" == "both" ]] && ufw allow "${PORT}/udp" >/dev/null 2>&1 || true
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
        [[ "$protocol_type" == "udp" || "$protocol_type" == "both" ]] && firewall-cmd --permanent --add-port="${PORT}/udp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
}

install_singbox(){
    local arch sb_ver url
    arch=$(detect_arch)

    echo -e "${YELLOW}正在安装 sing-box 最新版...${NC}"

    sb_ver=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/^v//')
    [[ -z "$sb_ver" || "$sb_ver" == "null" ]] && die "无法获取 sing-box 最新版本。"

    url="https://github.com/SagerNet/sing-box/releases/download/v${sb_ver}/sing-box-${sb_ver}-linux-${arch}.tar.gz"

    mkdir -p /tmp/sing-box-install
    rm -rf /tmp/sing-box-install/*

    wget -qO /tmp/sing-box-install/sb.tar.gz "$url" || die "下载 sing-box 失败。"
    tar -xzf /tmp/sing-box-install/sb.tar.gz -C /tmp/sing-box-install || die "解压 sing-box 失败。"

    find /tmp/sing-box-install -type f -name sing-box -exec mv {} "$SB_BIN" \;
    chmod +x "$SB_BIN" 2>/dev/null || true

    [[ ! -x "$SB_BIN" ]] && die "sing-box 安装失败，未找到可执行文件。"

    rm -rf /tmp/sing-box-install
    mkdir -p "$CONFIG_DIR" "$INFO_DIR"

    echo -e "${GREEN}sing-box 安装完成：v${sb_ver}${NC}"
}

create_singbox_service(){
cat > /etc/systemd/system/sing-box.service <<EOF2
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/etc/sing-box
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF2

    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1
}

restart_singbox(){
    systemctl restart sing-box
    sleep 1

    if ! systemctl is-active --quiet sing-box; then
        echo -e "${RED}sing-box 启动失败，最近日志如下：${NC}"
        journalctl -u sing-box -n 80 --no-pager || true
        exit 1
    fi

    echo -e "${GREEN}sing-box 已成功启动。${NC}"
}

print_qrcode(){
    local link="$1"

    if python3 - <<PY >/dev/null 2>&1
import qrcode
PY
    then
python3 <<PY
import qrcode
link = """$link"""
qr = qrcode.QRCode(version=1, border=1)
qr.add_data(link)
qr.make(fit=True)
qr.print_ascii(invert=True)
PY
    else
        echo -e "${YELLOW}未安装 qrcode Python 模块，跳过二维码输出。${NC}"
    fi
}

save_info(){
    local protocol="$1" protocol_name="$2" extra_json="$3"
    mkdir -p "$INFO_DIR"

    jq -n \
        --arg protocol "$protocol" \
        --arg protocol_name "$protocol_name" \
        --arg server "$IP" \
        --argjson port "$PORT" \
        --arg sni "$SNI" \
        --arg created_at "$(date '+%Y-%m-%d %H:%M:%S')" \
        --argjson extra "$extra_json" \
        '{protocol:$protocol,protocol_name:$protocol_name,server:$server,port:$port,sni:$sni,created_at:$created_at} + $extra' > "$INFO_FILE"
}

stop_existing(){
    systemctl stop sing-box 2>/dev/null || true
}

install_menu(){
    print_header
    echo -e "${YELLOW}请选择要部署的协议：${NC}"
    echo

    echo -e "${CYAN}1. VLESS + REALITY + Vision${NC}"
    echo -e "   协议特点：使用 VLESS + REALITY，模拟正常 HTTPS/TLS 连接，不需要域名和证书。"
    echo -e "   客户端：Shadowrocket、v2rayN、Nekoray、sing-box、Hiddify、Clash Meta/Mihomo 等。"
    echo -e "   抗封级别：★★★★★ 很高，当前免域名方案里综合表现较好。"
    echo -e "   推荐：★★★★★ 新手首选，适合大多数用户。"
    echo

    echo -e "${CYAN}2. Hysteria2${NC}"
    echo -e "   协议特点：使用 QUIC/UDP 传输，偏高速和抗丢包，适合网络不稳定时使用。"
    echo -e "   客户端：Shadowrocket、sing-box、Hiddify、Nekoray、Clash Meta/Mihomo 等。"
    echo -e "   抗封级别：★★★★☆ 较高，速度表现好，但不同网络环境差异较大。"
    echo -e "   推荐：★★★★☆ 高速节点，适合视频、下载和大流量。"
    echo

    echo -e "${CYAN}3. AnyTLS${NC}"
    echo -e "   协议特点：较新的 TLS 方向协议，目标是让代理连接更接近普通 TLS 流量。"
    echo -e "   客户端：Shadowrocket 新版本、sing-box、部分支持 AnyTLS 的客户端。"
    echo -e "   抗封级别：★★★★☆ 较高，新协议方向值得关注，生态仍在发展。"
    echo -e "   推荐：★★★☆☆ 备用测试，适合新版客户端用户。"
    echo

    echo -e "${CYAN}4. VLESS + gRPC + REALITY${NC}"
    echo -e "   协议特点：使用 VLESS + REALITY，并加入 gRPC 传输方式，和普通 TCP Reality 不同。"
    echo -e "   客户端：Shadowrocket、v2rayN、Nekoray、sing-box、Hiddify、Clash Meta/Mihomo 等。"
    echo -e "   抗封级别：★★★★☆ 较高，适合作为 VLESS Reality 的备用传输方式。"
    echo -e "   推荐：★★★☆☆ 备用方案，适合想多准备一个 VLESS 节点的用户。"
    echo

    echo -e "${CYAN}5. TUIC${NC}"
    echo -e "   协议特点：使用 QUIC/UDP 传输，偏低延迟和高速，路线和 Hysteria2 类似。"
    echo -e "   客户端：Shadowrocket、sing-box、Hiddify、Nekoray、Clash Meta/Mihomo 等。"
    echo -e "   抗封级别：★★★★☆ 较高，速度和低延迟表现好，但网络环境影响较大。"
    echo -e "   推荐：★★★★☆ 高速备用，适合视频、游戏和移动网络。"
    echo

    echo -e "${YELLOW}简单选择建议：${NC}"
    echo -e "不知道选哪个：选 1"
    echo -e "想要稳定：选 1"
    echo -e "想要速度：选 2 或 5"
    echo -e "想多一个备用节点：选 3 或 4"
    echo

    read -rp "请输入数字 [1-5]，默认 1: " CHOICE
    CHOICE=${CHOICE:-1}

    case "$CHOICE" in
        1) PROTOCOL_NAME="VLESS + REALITY + Vision" ;;
        2) PROTOCOL_NAME="Hysteria2" ;;
        3) PROTOCOL_NAME="AnyTLS" ;;
        4) PROTOCOL_NAME="VLESS + gRPC + REALITY" ;;
        5) PROTOCOL_NAME="TUIC" ;;
        *) die "无效选择。" ;;
    esac
}

prepare_install(){
    install_dependencies
    enable_bbr
    install_singbox

    IP=$(get_public_ip)
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PASS=$(openssl rand -hex 16)
    USER_NAME="user_$(openssl rand -hex 3)"
    SNI="www.microsoft.com"

    choose_port
}

deploy_vless_reality(){
    local keys priv pub sid extra_json
    stop_existing
    open_firewall_port "tcp"

    keys=$("$SB_BIN" generate reality-keypair)
    priv=$(echo "$keys" | grep -i "Private" | awk '{print $2}')
    pub=$(echo "$keys" | grep -i "Public" | awk '{print $2}')
    sid=$(openssl rand -hex 8)

    [[ -z "$priv" || -z "$pub" ]] && die "Reality 密钥生成失败。"

cat > "$CONFIG_FILE" <<EOF2
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "vless",
    "tag": "vless-reality-in",
    "listen": "::",
    "listen_port": ${PORT},
    "users": [{"name": "${USER_NAME}", "uuid": "${UUID}", "flow": "xtls-rprx-vision"}],
    "tls": {"enabled": true, "server_name": "${SNI}", "reality": {"enabled": true, "handshake": {"server": "${SNI}", "server_port": 443}, "private_key": "${priv}", "short_id": ["${sid}"]}}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF2

    extra_json=$(jq -n --arg public_key "$pub" --arg short_id "$sid" '{public_key:$public_key, short_id:$short_id, grpc_service_name:""}')
    save_info "vless-reality" "$PROTOCOL_NAME" "$extra_json"

    create_singbox_service
    restart_singbox
}

deploy_hysteria2(){
    local extra_json
    stop_existing
    open_firewall_port "both"

    mkdir -p "$CONFIG_DIR"

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CONFIG_DIR/hysteria2-key.pem" \
        -out "$CONFIG_DIR/hysteria2-cert.pem" \
        -days 3650 \
        -subj "/CN=${IP}" >/dev/null 2>&1

cat > "$CONFIG_FILE" <<EOF2
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "hysteria2",
    "tag": "hysteria2-in",
    "listen": "::",
    "listen_port": ${PORT},
    "users": [{"name": "${USER_NAME}", "password": "${PASS}"}],
    "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/hysteria2-cert.pem", "key_path": "${CONFIG_DIR}/hysteria2-key.pem"}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF2

    extra_json=$(jq -n '{}')
    save_info "hysteria2" "$PROTOCOL_NAME" "$extra_json"

    create_singbox_service
    restart_singbox
}

deploy_anytls(){
    local extra_json
    stop_existing
    open_firewall_port "tcp"

    mkdir -p "$CONFIG_DIR"

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CONFIG_DIR/anytls-key.pem" \
        -out "$CONFIG_DIR/anytls-cert.pem" \
        -days 3650 \
        -subj "/CN=${IP}" >/dev/null 2>&1

cat > "$CONFIG_FILE" <<EOF2
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "anytls",
    "tag": "anytls-in",
    "listen": "::",
    "listen_port": ${PORT},
    "users": [{"name": "${USER_NAME}", "password": "${PASS}"}],
    "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/anytls-cert.pem", "key_path": "${CONFIG_DIR}/anytls-key.pem"}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF2

    extra_json=$(jq -n '{}')
    save_info "anytls" "$PROTOCOL_NAME" "$extra_json"

    create_singbox_service
    restart_singbox
}

deploy_vless_grpc_reality(){
    local keys priv pub sid extra_json service_name
    service_name="grpc-service"

    stop_existing
    open_firewall_port "tcp"

    keys=$("$SB_BIN" generate reality-keypair)
    priv=$(echo "$keys" | grep -i "Private" | awk '{print $2}')
    pub=$(echo "$keys" | grep -i "Public" | awk '{print $2}')
    sid=$(openssl rand -hex 8)

    [[ -z "$priv" || -z "$pub" ]] && die "Reality 密钥生成失败。"

cat > "$CONFIG_FILE" <<EOF2
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "vless",
    "tag": "vless-grpc-reality-in",
    "listen": "::",
    "listen_port": ${PORT},
    "users": [{"name": "${USER_NAME}", "uuid": "${UUID}"}],
    "transport": {"type": "grpc", "service_name": "${service_name}"},
    "tls": {"enabled": true, "server_name": "${SNI}", "reality": {"enabled": true, "handshake": {"server": "${SNI}", "server_port": 443}, "private_key": "${priv}", "short_id": ["${sid}"]}}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF2

    extra_json=$(jq -n --arg public_key "$pub" --arg short_id "$sid" --arg service_name "$service_name" '{public_key:$public_key, short_id:$short_id, grpc_service_name:$service_name}')
    save_info "vless-grpc-reality" "$PROTOCOL_NAME" "$extra_json"

    create_singbox_service
    restart_singbox
}

deploy_tuic(){
    local extra_json alpn
    alpn="h3"

    stop_existing
    open_firewall_port "both"

    mkdir -p "$CONFIG_DIR"

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CONFIG_DIR/tuic-key.pem" \
        -out "$CONFIG_DIR/tuic-cert.pem" \
        -days 3650 \
        -subj "/CN=${IP}" >/dev/null 2>&1

cat > "$CONFIG_FILE" <<EOF2
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "tuic",
    "tag": "tuic-in",
    "listen": "::",
    "listen_port": ${PORT},
    "users": [{"name": "${USER_NAME}", "uuid": "${UUID}", "password": "${PASS}"}],
    "congestion_control": "bbr",
    "zero_rtt_handshake": false,
    "heartbeat": "10s",
    "tls": {"enabled": true, "alpn": ["${alpn}"], "certificate_path": "${CONFIG_DIR}/tuic-cert.pem", "key_path": "${CONFIG_DIR}/tuic-key.pem"}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF2

    extra_json=$(jq -n --arg alpn "$alpn" '{alpn:$alpn}')
    save_info "tuic" "$PROTOCOL_NAME" "$extra_json"

    create_singbox_service
    restart_singbox
}

generate_user_link(){
    local username="$1" protocol server port sni public_key short_id grpc_service_name alpn encoded_name uuid password link

    [[ ! -f "$INFO_FILE" || ! -f "$CONFIG_FILE" ]] && echo "" && return 1

    protocol=$(jq -r '.protocol' "$INFO_FILE")
    server=$(jq -r '.server' "$INFO_FILE")
    port=$(jq -r '.port' "$INFO_FILE")
    sni=$(jq -r '.sni // "www.microsoft.com"' "$INFO_FILE")
    public_key=$(jq -r '.public_key // empty' "$INFO_FILE")
    short_id=$(jq -r '.short_id // empty' "$INFO_FILE")
    grpc_service_name=$(jq -r '.grpc_service_name // "grpc-service"' "$INFO_FILE")
    alpn=$(jq -r '.alpn // "h3"' "$INFO_FILE")
    encoded_name=$(urlencode "$username")

    case "$protocol" in
        vless-reality)
            uuid=$(jq -r --arg name "$username" '.inbounds[0].users[] | select(.name==$name) | .uuid' "$CONFIG_FILE")
            link="vless://${uuid}@${server}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#${encoded_name}"
            ;;
        vless-grpc-reality)
            uuid=$(jq -r --arg name "$username" '.inbounds[0].users[] | select(.name==$name) | .uuid' "$CONFIG_FILE")
            link="vless://${uuid}@${server}:${port}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=grpc&serviceName=${grpc_service_name}#${encoded_name}"
            ;;
        hysteria2)
            password=$(jq -r --arg name "$username" '.inbounds[0].users[] | select(.name==$name) | .password' "$CONFIG_FILE")
            link="hysteria2://${password}@${server}:${port}?insecure=1#${encoded_name}"
            ;;
        anytls)
            password=$(jq -r --arg name "$username" '.inbounds[0].users[] | select(.name==$name) | .password' "$CONFIG_FILE")
            link="anytls://${password}@${server}:${port}/?sni=${sni}&insecure=1#${encoded_name}"
            ;;
        tuic)
            uuid=$(jq -r --arg name "$username" '.inbounds[0].users[] | select(.name==$name) | .uuid' "$CONFIG_FILE")
            password=$(jq -r --arg name "$username" '.inbounds[0].users[] | select(.name==$name) | .password' "$CONFIG_FILE")
            link="tuic://${uuid}:${password}@${server}:${port}?congestion_control=bbr&udp_relay_mode=native&alpn=${alpn}&allow_insecure=1#${encoded_name}"
            ;;
        *)
            link=""
            ;;
    esac

    echo "$link"
}

show_node_links_no_pause(){
    local protocol_name server port count i name link

    if [[ ! -f "$INFO_FILE" || ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}尚未安装任何协议。${NC}"
        return
    fi

    protocol_name=$(jq -r '.protocol_name' "$INFO_FILE")
    server=$(jq -r '.server' "$INFO_FILE")
    port=$(jq -r '.port' "$INFO_FILE")
    count=$(jq '.inbounds[0].users | length' "$CONFIG_FILE")

    echo -e "${YELLOW}当前协议：${NC}${protocol_name}"
    echo -e "${YELLOW}服务器：${NC}${server}"
    echo -e "${YELLOW}端口：${NC}${port}"
    echo -e "${YELLOW}用户数量：${NC}${count}"
    echo

    for ((i=0; i<count; i++)); do
        name=$(jq -r ".inbounds[0].users[$i].name // \"user_$i\"" "$CONFIG_FILE")
        link=$(generate_user_link "$name")

        echo -e "${CYAN}用户：${name}${NC}"
        echo "$link"
        echo
        echo -e "${YELLOW}二维码：${NC}"
        print_qrcode "$link"
        echo
    done
}

install_or_reinstall(){
    install_menu
    prepare_install

    case "$CHOICE" in
        1) deploy_vless_reality ;;
        2) deploy_hysteria2 ;;
        3) deploy_anytls ;;
        4) deploy_vless_grpc_reality ;;
        5) deploy_tuic ;;
    esac

    print_header
    echo -e "${GREEN}部署成功！${NC}"
    echo

    show_node_links_no_pause
    echo

    if [[ "$CHOICE" == "2" || "$CHOICE" == "5" ]]; then
        PORT_TYPE="UDP"
    else
        PORT_TYPE="TCP"
    fi

    echo -e "${RED}=================================================================${NC}"
    echo -e "${RED}⚠️  重要提醒：请先放行端口，再扫码连接${NC}"
    echo -e "${RED}=================================================================${NC}"
    echo
    echo -e "${YELLOW}必须修改 VPS 后台的防火墙策略 / 安全组规则${NC}"
    echo -e "${YELLOW}手动放行当前端口：${GREEN}${PORT}/${PORT_TYPE}${NC}"
    echo
    echo -e "当前协议：${GREEN}${PROTOCOL_NAME}${NC}"
    echo -e "当前端口：${GREEN}${PORT}${NC}"
    echo -e "端口类型：${GREEN}${PORT_TYPE}${NC}"
    echo
    echo -e "${RED}如果不放行端口，客户端可能无法连接。${NC}"
    echo -e "${RED}=================================================================${NC}"

    pause
}

show_node_links(){
    print_header
    show_node_links_no_pause
    pause
}

show_single_user_qr(){
    local name link

    [[ ! -f "$CONFIG_FILE" ]] && echo -e "${YELLOW}尚未安装协议。${NC}" && pause && return

    jq -r '.inbounds[0].users[].name' "$CONFIG_FILE"
    echo

    read -rp "请输入要生成二维码的用户名: " name

    if ! jq -e --arg name "$name" '.inbounds[0].users[] | select(.name==$name)' "$CONFIG_FILE" >/dev/null; then
        echo -e "${RED}用户不存在。${NC}"
        pause
        return
    fi

    link=$(generate_user_link "$name")

    echo
    echo -e "${CYAN}${link}${NC}"
    echo
    print_qrcode "$link"

    pause
}

update_singbox_core(){
    print_header
    echo -e "${YELLOW}即将更新 sing-box 内核到 GitHub 最新版本。${NC}"
    echo -e "${YELLOW}更新前会先备份当前配置。${NC}"
    echo

    [[ ! -f "$CONFIG_FILE" ]] && echo -e "${RED}未找到当前配置文件：${CONFIG_FILE}${NC}" && pause && return

    BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"

    echo -e "${GREEN}已备份当前配置到：${BACKUP_FILE}${NC}"
    echo

    if [[ -x "$SB_BIN" ]]; then
        echo -e "${YELLOW}当前 sing-box 版本：${NC}"
        "$SB_BIN" version || true
        echo
    fi

    read -rp "确认更新 sing-box 内核？输入 yes 继续: " confirm
    [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}已取消更新。${NC}" && pause && return

    systemctl stop sing-box 2>/dev/null || true

    install_singbox

    echo
    echo -e "${YELLOW}正在检查当前配置是否兼容新版 sing-box...${NC}"

    if "$SB_BIN" check -c "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}配置检查通过。${NC}"
    else
        echo -e "${RED}配置检查失败，正在恢复备份配置。${NC}"
        "$SB_BIN" check -c "$CONFIG_FILE" || true
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        systemctl restart sing-box 2>/dev/null || true
        pause
        return
    fi

    systemctl restart sing-box

    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}sing-box 内核更新完成，服务已成功重启。${NC}"
        echo
        echo -e "${YELLOW}更新后 sing-box 版本：${NC}"
        "$SB_BIN" version || true
    else
        echo -e "${RED}更新后 sing-box 启动失败，正在恢复备份配置。${NC}"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        systemctl restart sing-box 2>/dev/null || true
        journalctl -u sing-box -n 80 --no-pager || true
    fi

    pause
}

service_menu(){
    while true; do
        print_header
        echo -e "${YELLOW}服务管理${NC}"
        echo
        echo "1. 启动 sing-box"
        echo "2. 停止 sing-box"
        echo "3. 重启 sing-box"
        echo "4. 查看当前状态"
        echo "5. 查看实时日志"
        echo "6. 更新 sing-box 内核"
        echo "0. 返回主菜单"
        echo

        read -rp "请选择: " choice

        case "$choice" in
            1)
                systemctl start sing-box
                systemctl status sing-box --no-pager
                pause
                ;;
            2)
                systemctl stop sing-box
                echo -e "${GREEN}已停止 sing-box。${NC}"
                pause
                ;;
            3)
                systemctl restart sing-box
                systemctl status sing-box --no-pager
                pause
                ;;
            4)
                systemctl status sing-box --no-pager
                pause
                ;;
            5)
                echo -e "${YELLOW}按 Ctrl+C 退出日志查看。${NC}"
                sleep 1
                journalctl -u sing-box -f --no-pager
                ;;
            6)
                update_singbox_core
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择。${NC}"
                sleep 1
                ;;
        esac
    done
}

list_users(){
    print_header

    [[ ! -f "$CONFIG_FILE" ]] && echo -e "${YELLOW}尚未安装协议。${NC}" && pause && return

    echo -e "${YELLOW}当前用户列表：${NC}"
    echo

    jq -r '.inbounds[0].users[] | "- " + (.name // "未命名")' "$CONFIG_FILE"

    pause
}

add_user(){
    local protocol name uuid pass tmpfile link

    [[ ! -f "$INFO_FILE" || ! -f "$CONFIG_FILE" ]] && echo -e "${YELLOW}尚未安装协议。${NC}" && pause && return

    protocol=$(jq -r '.protocol' "$INFO_FILE")

    read -rp "请输入新用户名，只能使用英文、数字、下划线，直接回车自动生成: " name
    [[ -z "$name" ]] && name="user_$(openssl rand -hex 3)"

    if ! [[ "$name" =~ ^[A-Za-z0-9_]+$ ]]; then
        echo -e "${RED}用户名只能包含英文、数字、下划线。${NC}"
        pause
        return
    fi

    if jq -e --arg name "$name" '.inbounds[0].users[] | select(.name==$name)' "$CONFIG_FILE" >/dev/null; then
        echo -e "${RED}用户名已存在。${NC}"
        pause
        return
    fi

    uuid=$(cat /proc/sys/kernel/random/uuid)
    pass=$(openssl rand -hex 16)
    tmpfile="/tmp/sing-box-config-$$.json"

    case "$protocol" in
        vless-reality)
            jq --arg name "$name" --arg uuid "$uuid" \
                '.inbounds[0].users += [{"name":$name,"uuid":$uuid,"flow":"xtls-rprx-vision"}]' \
                "$CONFIG_FILE" > "$tmpfile"
            ;;
        vless-grpc-reality)
            jq --arg name "$name" --arg uuid "$uuid" \
                '.inbounds[0].users += [{"name":$name,"uuid":$uuid}]' \
                "$CONFIG_FILE" > "$tmpfile"
            ;;
        hysteria2|anytls)
            jq --arg name "$name" --arg pass "$pass" \
                '.inbounds[0].users += [{"name":$name,"password":$pass}]' \
                "$CONFIG_FILE" > "$tmpfile"
            ;;
        tuic)
            jq --arg name "$name" --arg uuid "$uuid" --arg pass "$pass" \
                '.inbounds[0].users += [{"name":$name,"uuid":$uuid,"password":$pass}]' \
                "$CONFIG_FILE" > "$tmpfile"
            ;;
        *)
            echo -e "${RED}未知协议，无法添加用户。${NC}"
            pause
            return
            ;;
    esac

    if "$SB_BIN" check -c "$tmpfile" >/dev/null 2>&1; then
        mv "$tmpfile" "$CONFIG_FILE"
        systemctl restart sing-box

        link=$(generate_user_link "$name")

        echo -e "${GREEN}用户添加成功：${name}${NC}"
        echo
        echo -e "${YELLOW}用户节点链接：${NC}"
        echo "$link"
        echo
        echo -e "${YELLOW}二维码：${NC}"
        print_qrcode "$link"
    else
        echo -e "${RED}新配置校验失败，未修改。${NC}"
        "$SB_BIN" check -c "$tmpfile" || true
        rm -f "$tmpfile"
    fi

    pause
}

delete_user(){
    local name count tmpfile

    [[ ! -f "$CONFIG_FILE" ]] && echo -e "${YELLOW}尚未安装协议。${NC}" && pause && return

    count=$(jq '.inbounds[0].users | length' "$CONFIG_FILE")

    (( count <= 1 )) && echo -e "${RED}当前只有 1 个用户，不能删除最后一个用户。${NC}" && pause && return

    echo -e "${YELLOW}当前用户：${NC}"
    jq -r '.inbounds[0].users[] | "- " + (.name // "未命名")' "$CONFIG_FILE"
    echo

    read -rp "请输入要删除的用户名: " name

    if ! jq -e --arg name "$name" '.inbounds[0].users[] | select(.name==$name)' "$CONFIG_FILE" >/dev/null; then
        echo -e "${RED}用户不存在。${NC}"
        pause
        return
    fi

    tmpfile="/tmp/sing-box-config-$$.json"

    jq --arg name "$name" '.inbounds[0].users = (.inbounds[0].users | map(select(.name != $name)))' "$CONFIG_FILE" > "$tmpfile"

    if "$SB_BIN" check -c "$tmpfile" >/dev/null 2>&1; then
        mv "$tmpfile" "$CONFIG_FILE"
        systemctl restart sing-box
        echo -e "${GREEN}用户已删除：${name}${NC}"
    else
        echo -e "${RED}新配置校验失败，未修改。${NC}"
        "$SB_BIN" check -c "$tmpfile" || true
        rm -f "$tmpfile"
    fi

    pause
}

user_menu(){
    while true; do
        print_header
        echo -e "${YELLOW}用户管理${NC}"
        echo
        echo "1. 查看用户"
        echo "2. 增加用户"
        echo "3. 删除用户"
        echo "4. 生成指定用户二维码"
        echo "0. 返回主菜单"
        echo

        read -rp "请选择: " choice

        case "$choice" in
            1) list_users ;;
            2) add_user ;;
            3) delete_user ;;
            4) show_single_user_qr ;;
            0) return ;;
            *)
                echo -e "${RED}无效选择。${NC}"
                sleep 1
                ;;
        esac
    done
}

uninstall_all(){
    print_header
    echo -e "${RED}此操作将卸载 sing-box 并删除所有配置。${NC}"

    read -rp "确认卸载？输入 yes 继续: " confirm

    [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}已取消。${NC}" && pause && return

    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true

    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload

    rm -rf "$CONFIG_DIR" "$INFO_DIR"
    rm -f "$SB_BIN"

    echo -e "${GREEN}卸载完成。${NC}"

    pause
}

main_menu(){
    while true; do
        print_header

        if [[ -f "$INFO_FILE" ]]; then
            echo -e "${GREEN}当前已安装：$(jq -r '.protocol_name' "$INFO_FILE") | 端口：$(jq -r '.port' "$INFO_FILE")${NC}"

            if systemctl is-active --quiet sing-box; then
                echo -e "${GREEN}服务状态：运行中${NC}"
            else
                echo -e "${YELLOW}服务状态：未运行${NC}"
            fi
        else
            echo -e "${YELLOW}当前状态：尚未安装协议${NC}"
        fi

        echo
        echo "1. 安装 / 重装协议"
        echo "2. 管理当前服务"
        echo "3. 用户管理"
        echo "4. 查看当前节点链接"
        echo "5. 卸载"
        echo "0. 退出"
        echo

        read -rp "请选择: " choice

        case "$choice" in
            1) install_or_reinstall ;;
            2) service_menu ;;
            3) user_menu ;;
            4) show_node_links ;;
            5) uninstall_all ;;
            0) exit 0 ;;
            *)
                echo -e "${RED}无效选择。${NC}"
                sleep 1
                ;;
        esac
    done
}

main(){
    check_root
    main_menu
}

main "$@"
