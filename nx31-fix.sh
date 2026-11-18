#!/bin/sh
# NX31: разовое «оздоровление» уже установленной системы.
# Идемпотентен — можно запускать повторно.
#
#   sh /etc/nx31-fix.sh
#
# Что делает:
#   1. расширяет /overlay (16 МБ -> ~45 МБ) за счёт свободных LEB на флеше
#   2. убирает мусор из логов (redsocks log_info=off) и глушит printk в консоль
#   3. добавляет резервный DNS, чтобы смерть DoH не убивала интернет
#   4. поднимает супервизор всей цепочки (xray/redsocks/DoH/firewall/WAN)

say() { echo "[*] $*"; }

# ---------- 1. место на флеше ----------

grow_overlay() {
    LEB=$(ubinfo /dev/ubi0 2>/dev/null | awk '/Logical eraseblock size/{print $4}')
    FREE=$(ubinfo /dev/ubi0 2>/dev/null | awk '/Amount of available logical eraseblocks/{print $6}')
    CUR=$(ubinfo /dev/ubi0 -N 6 2>/dev/null | awk '/Size:/{print $2}')

    [ -z "$LEB" ] && { say "ubinfo не отвечает, пропускаю"; return 1; }
    [ -z "$FREE" ] && { say "не смог прочитать свободные LEB"; return 1; }
    [ -z "$CUR" ] && CUR=133

    ADD=$((FREE / 2))
    if [ "$ADD" -lt 20 ]; then
        say "флеш уже расширен (свободно $FREE LEB), пропускаю"
        return 0
    fi

    NEW=$((CUR + ADD))
    say "rootfs_data: $CUR -> $NEW LEB (+$((ADD * LEB / 1048576)) MiB)"
    if ubirsvol /dev/ubi0 -n 6 -s $((NEW * LEB)); then
        mount -o remount / 2>/dev/null
        df -h /overlay | tail -1
    else
        say "ubirsvol не сработал — overlay останется прежним"
        return 1
    fi
}

# ---------- 2. логи ----------

quiet_logs() {
    # консоль — только panic; в dmesg остаются предупреждения и OOM
    echo "1 4 1 7" > /proc/sys/kernel/printk 2>/dev/null
    mkdir -p /etc/sysctl.d
    echo "kernel.printk = 1 4 1 7" > /etc/sysctl.d/99-nx31-quiet.conf
    grep -q '^kernel.printk' /etc/sysctl.conf 2>/dev/null || \
        echo 'kernel.printk = 1 4 1 7' >> /etc/sysctl.conf
    say "printk: консоль заглушена, dmesg сохранён"

    if grep -q 'log_info = on;' /etc/redsocks.conf 2>/dev/null; then
        sed -i 's/log_info = on;/log_info = off;/' /etc/redsocks.conf
        say "redsocks: log_info=off"
        /etc/init.d/redsocks restart >/dev/null 2>&1
    fi
}

# ---------- 3. DNS ----------

dns_fallback() {
    uci -q del_list dhcp.@dnsmasq[0].server='1.1.1.1'
    uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
    uci set dhcp.@dnsmasq[0].strictorder='1'
    if uci commit dhcp; then
        /etc/init.d/dnsmasq reload >/dev/null 2>&1
        say "DNS: DoH первым, 1.1.1.1 как резерв"
    else
        say "DNS: uci commit не прошёл (нет места?)"
    fi
}

# ---------- 4. супервизор ----------

supervisor() {
    for pid in $(ps w 2>/dev/null | awk '/[x]ray-watchdog\.sh/{print $1}'); do
        kill "$pid" 2>/dev/null
    done
    sleep 1
    [ -f /etc/xray-watchdog.sh.bak ] && rm -f /etc/xray-watchdog.sh.bak
    chmod +x /etc/xray-watchdog.sh /etc/xray-updater.sh 2>/dev/null
    start-stop-daemon -S -b -x /etc/xray-watchdog.sh 2>/dev/null
    sleep 2
    if ps w 2>/dev/null | grep -q '[/]etc/xray-watchdog.sh'; then
        say "супервизор запущен"
    else
        say "ОШИБКА: супервизор не стартовал"
    fi
}

say "=== NX31 fix ==="
grow_overlay
quiet_logs
dns_fallback
supervisor
sync
say "=== готово ==="
df -h /overlay | tail -1
free -m | head -2
