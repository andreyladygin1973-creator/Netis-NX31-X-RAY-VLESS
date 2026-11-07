#!/bin/sh

echo "Setting up repositories..."
cat > /etc/opkg/distfeeds.conf << 'EOF'
src/gz openwrt_base https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/base
src/gz openwrt_luci https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/luci
src/gz openwrt_packages https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/packages
src/gz openwrt_routing https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/routing
EOF

echo "Installing packages..."
opkg update
# libustream и curl нужны для HTTPS-запросов (wget в BusyBox без них не работает)
opkg install openssh-sftp-server redsocks https-dns-proxy libustream-openssl ca-bundle curl || true

echo "Creating redsocks config..."
cat > /etc/redsocks.conf << 'EOF'
base {
    log_debug = off;
    log_info = on;
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 1080;
    type = socks5;
}
EOF

echo "Creating https-dns-proxy config..."
mkdir -p /etc/config
cat > /etc/config/https-dns-proxy << 'EOF'
config main 'config'
        option update_dnsmasq_config '*'
        option force_dns '1'
        list force_dns_port '53'
        list force_dns_port '853'

config https-dns-proxy
        option listen_addr '127.0.0.1'
        option listen_port '5054'
        option user 'nobody'
        option group 'nogroup'
        option bootstrap_dns '77.88.8.8'
        option resolver_url 'https://1.1.1.1/dns-query'
EOF

# ==========================================
# ОЧИСТКА СТОКОВОЙ ПРОШИВКИ ОТ 5053
# ==========================================
echo "Cleaning up stock 5053 DoH reference..."
cp /etc/config/dhcp /etc/config/dhcp.bak.$(date +%Y%m%d%H%M) 2>/dev/null

uci -q del_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'
uci -q del_list dhcp.@dnsmasq[0].doh_backup_server='127.0.0.1#5053'

# Убеждаемся, что 5054 в server
uci -q get dhcp.@dnsmasq[0].server | grep -q '5054' || \
    uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'

# То же для backup — чтобы STOP корректно отработал
uci -q get dhcp.@dnsmasq[0].doh_backup_server | grep -q '5054' || \
    uci add_list dhcp.@dnsmasq[0].doh_backup_server='127.0.0.1#5054'

uci commit dhcp
# ==========================================

echo "Creating firewall.user (persistent iptables rules)..."
cat > /etc/firewall.user << 'EOF'
#!/bin/sh
# Базовый NAT
iptables -t nat -C POSTROUTING -o eth1 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# Создаём/чистим цепочку REDSOCKS
iptables -t nat -N REDSOCKS 2>/dev/null
iptables -t nat -F REDSOCKS

iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -d 78.17.171.64 -j RETURN
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345

# ==========================================
# 1. Блокируем QUIC (UDP 443) ДО применения REDSOCKS
# ==========================================
iptables -t filter -C FORWARD -i br-lan -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || \
    iptables -t filter -I FORWARD -i br-lan -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable

# То же для IPv6 (на случай если клиент получит IPv6)
ip6tables -t filter -C FORWARD -i br-lan -p udp --dport 443 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || \
    ip6tables -t filter -I FORWARD -i br-lan -p udp --dport 443 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null

# ==========================================
# 2. PREROUTING (Клиенты)
# ==========================================
# Сбрасываем старые правила для PREROUTING, чтобы избежать дублей
while iptables -t nat -D PREROUTING -i br-lan -j REDSOCKS 2>/dev/null; do :; done
while iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null; do :; done
while iptables -t nat -D PREROUTING -i br-lan -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null; do :; done

# ВАЖНО: DNS-редирект должен быть СТРОГО ПЕРЕД REDSOCKS!
iptables -t nat -A PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -i br-lan -p tcp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -i br-lan -j REDSOCKS

# ==========================================
# 3. Сам роутер (OUTPUT)
# ==========================================
# Очищаем только наши правила, не ломая нативные цепочки fw3
while iptables -t nat -D OUTPUT -d 78.17.171.64 -j RETURN 2>/dev/null; do :; done
for ip in 1.1.1.1 8.8.8.8 9.9.9.9; do
    while iptables -t nat -D OUTPUT -d $ip -p tcp --dport 443 -j REDSOCKS 2>/dev/null; do :; done
    iptables -t nat -A OUTPUT -d $ip -p tcp --dport 443 -j REDSOCKS
done
iptables -t nat -I OUTPUT 1 -d 78.17.171.64 -j RETURN

# MSS Clamping
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Перезапускаем DoH только если он упал
if ! pidof https-dns-proxy >/dev/null 2>&1; then
    /etc/init.d/https-dns-proxy restart 2>/dev/null
fi
EOF
chmod +x /etc/firewall.user

echo "Creating rc.local (services only)..."
cat > /etc/rc.local << 'EOF'
#!/bin/sh
sleep 30

# Ждём интернет (максимум 60 секунд, не зависаем навсегда)
waited=0
while [ $waited -lt 60 ]; do
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 77.88.8.8 >/dev/null 2>&1; then
        break
    fi
    sleep 3
    waited=$((waited + 3))
done

# 1. Восстанавливаем Xray из флешки в память
if [ ! -f /tmp/xray ]; then
    if [ -s /etc/xray/xray ]; then
        cp /etc/xray/xray /tmp/xray
        chmod +x /tmp/xray
    fi
fi

export GOGC=20
export GOMEMLIMIT=50MiB

# 2. Запуск Xray (только если еще не запущен)
if ! pidof xray >/dev/null 2>&1; then
    /etc/xray-updater.sh
fi

# 3. redsocks
/etc/init.d/redsocks restart 2>/dev/null
sleep 2

# 4. Применяем правила firewall.user
sh /etc/firewall.user

# 5. Обновляем конфиг dnsmasq через UCI (вместо sed по cfg-файлу)
uci set dhcp.@dnsmasq[0].noresolv='1'
uci -q del_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'
uci commit dhcp
/etc/init.d/dnsmasq reload 2>/dev/null

# 6. Watchdog (только если не запущен)
if ! ps w | grep -q '[/]etc/xray-watchdog.sh'; then
    start-stop-daemon -S -b -x /etc/xray-watchdog.sh 2>/dev/null
fi

# 7. Отключаем wireguard
/etc/init.d/wireguard stop 2>/dev/null
/etc/init.d/wireguard disable 2>/dev/null
killall wireguard_watchdog 2>/dev/null

exit 0
EOF
chmod +x /etc/rc.local

echo "Creating hotplug (dnsmasq fix after ifup)..."
mkdir -p /etc/hotplug.d/iface
cat > /etc/hotplug.d/iface/99-doh-fix << 'EOF'
#!/bin/sh
if [ "$ACTION" = "ifup" ]; then
    (
        sleep 5
        /etc/init.d/https-dns-proxy restart 2>/dev/null
        
        # Используем UCI вместо sed
        uci set dhcp.@dnsmasq[0].noresolv='1'
        uci -q del_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'
        uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'
        uci commit dhcp
        /etc/init.d/dnsmasq reload 2>/dev/null
    ) >/dev/null 2>&1 &
fi
EOF
chmod +x /etc/hotplug.d/iface/99-doh-fix

echo "Preparing Xray (UPX 10MB, NO gzip)..."
mkdir -p /etc/xray
rm -f /etc/xray/xray.gz /etc/xray/xray.xz
if [ -f /tmp/xray ]; then
    cp /tmp/xray /etc/xray/xray
    chmod +x /etc/xray/xray
    chmod +x /tmp/xray
    echo "Xray copied: $(wc -c < /etc/xray/xray) bytes"
else
    echo "ERROR: /tmp/xray not found!"
fi

mv /tmp/config.template.json /etc/xray/ 2>/dev/null
mv /tmp/xray-updater.sh /etc/ 2>/dev/null
mv /tmp/xray-watchdog.sh /etc/ 2>/dev/null
chmod +x /etc/xray-updater.sh /etc/xray-watchdog.sh

echo "Installing web interface..."
mkdir -p /www/cgi-bin
mv /tmp/vless.html /www/ 2>/dev/null
mv /tmp/vless.cgi /www/cgi-bin/vless 2>/dev/null
chmod +x /www/cgi-bin/vless

echo "Updating header.js..."
if [ -f "/tmp/header.js" ]; then
    cp /tmp/header.js /www/js/publicPlugin/header.js
    chmod 644 /www/js/publicPlugin/header.js
fi

echo "Hiding unwanted menu items..."
if [ -f /www/application.html ]; then
    sed -i '/<\/head>/i <style>a[href*="openvpn"], a[href*="wireguard"], a[href*="qos"], a[href*="ddns"], a[href*="tr069"] { display: none !important; }</style>' /www/application.html
fi

echo "Configuring URLs..."
if [ -f /tmp/urls.txt ]; then
    SUB=$(grep 'SUB_URL=' /tmp/urls.txt | cut -d'=' -f2- | tr -d '"\r')
    DIR=$(grep 'DIRECT_URL=' /tmp/urls.txt | cut -d'=' -f2- | tr -d '"\r')
    ESC_SUB=$(echo "$SUB" | sed 's/&/\\&/g; s/|/\\|/g')
    ESC_DIR=$(echo "$DIR" | sed 's/&/\\&/g; s/|/\\|/g')
    sed -i "s|^SUB_URL=.*|SUB_URL=\"$ESC_SUB\"|" /etc/xray-updater.sh
    sed -i "s|^DIRECT_URL=.*|DIRECT_URL=\"$ESC_DIR\"|" /etc/xray-updater.sh
fi

echo "Setup complete! (reboot to activate rc.local)"