#!/bin/sh
# NX31 supervisor v2
# Следит за ВСЕЙ цепочкой: xray -> redsocks -> DoH -> firewall -> WAN.
# В отличие от v1 проверяет работоспособность, а не только pidof.
#
# Запуск:  start-stop-daemon -S -b -x /etc/xray-watchdog.sh

XRAY_BIN=/tmp/xray
XRAY_BAK=/etc/xray/xray
XRAY_CONF=/etc/xray/config.json
SUP_LOG=/tmp/supervisor.log
BB_LOG=/tmp/blackbox.log
BB_DIR=/overlay/blackbox
LOCK=/tmp/supervisor.lock
CNT=/tmp/supervisor.restarts

export GOGC="${GOGC:-40}"
export GOMEMLIMIT="${GOMEMLIMIT:-40MiB}"

log() {
    logger -t xray-sup "$*" 2>/dev/null
    echo "$(date '+%F %T') $*" >> "$SUP_LOG" 2>/dev/null
}

rotate() {
    f="$1"; n="$2"
    lines=$(wc -l < "$f" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$n" ]; then
        tail -n $((n / 2)) "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
    fi
}

listen() {
    netstat -ltn 2>/dev/null | grep -q ":$1 "
}

memavail() { awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo 2>/dev/null; }

xray_rss() {
    p=$(pidof xray 2>/dev/null | awk '{print $1}')
    [ -n "$p" ] && awk '/^VmRSS:/{print int($2/1024)}' /proc/$p/status 2>/dev/null
}

tunnel_ok() {
    # Проверяем реальный проход через туннель, а не только открытый порт.
    # Два разных endpoint'а, чтобы не рвать соединение из-за блокировки одного.
    for url in https://www.gstatic.com/generate_204 https://cp.cloudflare.com/generate_204; do
        code=$(curl -s -m 12 -o /dev/null -x socks5h://127.0.0.1:1080 \
               -w '%{http_code}' "$url" 2>/dev/null)
        [ "$code" = "204" ] && return 0
    done
    return 1
}

dns_ok() {
    nslookup www.google.com 127.0.0.1 >/dev/null 2>&1
}

wan_ok() {
    ip route 2>/dev/null | grep -q '^default via'
}

inet_ok() {
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 77.88.8.8 >/dev/null 2>&1
}

upstream() { ip route 2>/dev/null | awk '/^default via/{print $3; exit}'; }
carrier()  { cat /sys/class/net/eth1/carrier 2>/dev/null; }

rules_ok() {
    iptables -t nat -C PREROUTING -i br-lan -j REDSOCKS >/dev/null 2>&1
}

# ---------- восстановление ----------

restore_xray_bin() {
    if [ ! -x "$XRAY_BIN" ] && [ -s "$XRAY_BAK" ]; then
        log "xray: binary missing, restoring from flash"
        cp "$XRAY_BAK" "$XRAY_BIN" && chmod +x "$XRAY_BIN"
    fi
}

restart_xray() {
    log "xray: restart (reason: $1)"
    restore_xray_bin
    killall xray 2>/dev/null
    sleep 1
    killall -9 xray 2>/dev/null

    if ! "$XRAY_BIN" -test -c "$XRAY_CONF" >/dev/null 2>&1; then
        if [ -s "${XRAY_CONF}.bak" ]; then
            log "xray: config invalid, rolling back to .bak"
            cp "${XRAY_CONF}.bak" "$XRAY_CONF"
        else
            log "xray: config invalid and no backup, trying subscription refresh"
            sh /etc/xray-updater.sh >/dev/null 2>&1
        fi
    fi

    start-stop-daemon -S -b -x "$XRAY_BIN" -- -c "$XRAY_CONF" 2>/dev/null
    sleep 2
    if pidof xray >/dev/null 2>&1; then
        log "xray: restarted ok"
    else
        log "xray: FAILED to start"
    fi
}

restart_redsocks() {
    log "redsocks: restart"
    # init-скрипт делает stop без ожидания: старый процесс ещё держит :12345,
    # и новый падает с EADDRINUSE (SO_REUSEADDR в redsocks не выставлен).
    # Поэтому останавливаем, ждём освобождения порта и только потом стартуем.
    /etc/init.d/redsocks stop >/dev/null 2>&1

    i=0
    while [ $i -lt 10 ] && netstat -ltn 2>/dev/null | grep -q ':12345 '; do
        sleep 1
        i=$((i + 1))
    done

    if pidof redsocks >/dev/null 2>&1; then
        log "redsocks: port still busy after ${i}s, killing"
        killall -9 redsocks >/dev/null 2>&1
        sleep 1
    fi

    /etc/init.d/redsocks start >/dev/null 2>&1
}

restart_doh() {
    log "doh: restart https-dns-proxy + dnsmasq"
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1
    sleep 4
    /etc/init.d/dnsmasq reload >/dev/null 2>&1
}

restore_rules() {
    log "firewall: REDSOCKS rules missing, re-applying firewall.user"
    sh /etc/firewall.user >/dev/null 2>&1
}

restore_wan() {
    log "wan: no default route, ifup wan1"
    ifup wan1 >/dev/null 2>&1
}

budget() {
    n=$(cat "$CNT" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$CNT"
    [ "$n" -le 30 ]
}

# ---------- чёрный ящик ----------

bb() {
    echo "$(date '+%F %T') state=$1 detail=$2 memavail=$(memavail)MB xray_rss=$(xray_rss)MB \
redsocks=$(listen 12345 && echo up || echo down) xray=$(pidof xray >/dev/null 2>&1 && echo up || echo down)" >> "$BB_LOG"
    rotate "$BB_LOG" 3000
}

dump_blackbox() {
    mkdir -p "$BB_DIR" 2>/dev/null
    f="$BB_DIR/fail-$(date '+%Y%m%d-%H%M%S').log"
    {
        echo "=== snapshot $(date) ==="
        cat "$BB_LOG" 2>/dev/null | tail -60
        echo "--- mem ---";   free -m 2>/dev/null
        echo "--- procs ---"; ps w 2>/dev/null | grep -E '[x]ray|[r]edsocks|[h]ttps-dns|[d]nsmasq'
        echo "--- route ---"; ip route 2>/dev/null
        echo "--- dmesg tail ---"; dmesg 2>/dev/null | tail -40
        echo "--- log tail ---"; logread 2>/dev/null | tail -60
    } > "$f" 2>/dev/null
    log "blackbox saved: $f"
    # держим только 5 последних
    ls -1t "$BB_DIR"/fail-*.log 2>/dev/null | tail -n +6 | while read -r old; do rm -f "$old"; done
}

# ---------- основной цикл ----------

# Защита от второго экземпляра.
# flock здесь не годится: дочерние процессы (sleep/curl) наследуют fd блокировки,
# и после kill супервизора осиротевший ребёнок держит лок до своего завершения —
# новый экземпляр не может стартовать. Поэтому pidfile + проверка cmdline.
if [ -f "$LOCK" ]; then
    old=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null \
       && grep -q 'xray-watchdog' "/proc/$old/cmdline" 2>/dev/null; then
        log "another supervisor instance (pid $old) is running, exit"
        exit 0
    fi
fi
echo $$ > "$LOCK"

log "supervisor v2 started (pid $$)"

cycle=0
prev_state="init"
prev_hour=$(date +%H)
wfail=$(cat /tmp/wanfail 2>/dev/null || echo 0)

while true; do
    cycle=$((cycle + 1))

    hour=$(date +%H)
    if [ "$hour" != "$prev_hour" ]; then
        prev_hour="$hour"
        echo 0 > "$CNT"
    fi

    # 1. железо и базовая связность
    if ! wan_ok; then
        bb "WAN_DOWN" "no default route"
        [ "$prev_state" != "WAN_DOWN" ] && dump_blackbox
        prev_state="WAN_DOWN"
        budget && restore_wan
        sleep 30
        continue
    fi

    # 1b. аплинк: маршрут есть, но наружу не пробиваемся.
    # Это НЕ проблема xray/redsocks (ICMP не проходит через них) — смотрим WAN.
    if ! inet_ok; then
        wfail=$((wfail + 1))
        echo "$wfail" > /tmp/wanfail
        if [ "$wfail" -eq 1 ]; then
            log "wan: uplink unreachable (carrier=$(carrier) via=$(upstream))"
            bb "WAN_UNREACH" "carrier=$(carrier) via=$(upstream)"
            dump_blackbox
        fi
        if [ "$wfail" -ge 10 ]; then
            log "wan: 5 min without uplink, renewing wan1"
            ifup wan1 >/dev/null 2>&1
            wfail=0
            echo 0 > /tmp/wanfail
        fi
        sleep 30
        continue
    elif [ "$wfail" -gt 0 ]; then
        log "wan: uplink recovered after ~$((wfail * 30))s"
        echo "wan recovery after ~$((wfail * 30))s" >> "$BB_LOG"
        wfail=0
        echo 0 > /tmp/wanfail
    fi

    # 2. правила firewall
    if ! rules_ok; then
        bb "RULES_LOST" "PREROUTING REDSOCKS"
        [ "$prev_state" != "RULES_LOST" ] && dump_blackbox
        prev_state="RULES_LOST"
        budget && restore_rules
    fi

    # 3. redsocks
    if ! listen 12345; then
        bb "REDSOCKS_DOWN" "port 12345"
        [ "$prev_state" != "REDSOCKS_DOWN" ] && dump_blackbox
        prev_state="REDSOCKS_DOWN"
        budget && restart_redsocks
        sleep 5
    fi

    # 4. xray: процесс + порт
    if ! listen 1080 || ! pidof xray >/dev/null 2>&1; then
        bb "XRAY_DOWN" "port/pid"
        [ "$prev_state" != "XRAY_DOWN" ] && dump_blackbox
        prev_state="XRAY_DOWN"
        budget && restart_xray
    fi

    # 5. тяжёлые проверки — раз в 4 цикла (~2 мин)
    if [ $((cycle % 4)) -eq 0 ]; then
        if ! tunnel_ok; then
            bb "TUNNEL_DEAD" "socks probe failed"
            [ "$prev_state" != "TUNNEL_DEAD" ] && dump_blackbox
            prev_state="TUNNEL_DEAD"
            budget && restart_xray "tunnel probe failed"
        fi

        if ! dns_ok; then
            bb "DNS_DEAD" "nslookup via 127.0.0.1"
            [ "$prev_state" != "DNS_DEAD" ] && dump_blackbox
            prev_state="DNS_DEAD"
            budget && restart_doh
        fi
    fi

    if [ "$prev_state" != "OK" ]; then
        if dns_ok && tunnel_ok; then
            log "chain recovered"
        fi
        prev_state="OK"
    fi

    bb "OK" "cycle=$cycle"
    rotate "$SUP_LOG" 800
    sleep 30
done
