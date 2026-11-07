#!/bin/sh
CONFIG_FILE="/etc/xray-updater.sh"
WATCHDOG_FILE="/etc/xray-watchdog.sh"
XRAY_BIN="/tmp/xray"
XRAY_CONF="/etc/xray/config.json"

json_escape() {
    printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

url_decode() {
    sed 's/%3[Aa]/:/g; s/%2[Ff]/\//g; s/%3[Ff]/?/g; s/%3[Dd]/=/g; s/%26/\&/g; s/%20/ /g; s/%2[Bb]/+/g; s/%40/@/g; s/%23/#/g; s/%25/%/g; s/%5[Bb]/[/g; s/%5[Dd]/]/g'
}

echo "Content-Type: application/json"
echo ""

if [ "$REQUEST_METHOD" = "POST" ]; then
    POST_DATA=$(cat)
    ACTION=$(printf '%s' "$POST_DATA" | tr '&' '\n' | grep '^ACTION=' | head -1 | cut -d= -f2-)

    if [ "$ACTION" = "stop" ]; then
        [ -f "$WATCHDOG_FILE" ] && mv "$WATCHDOG_FILE" "${WATCHDOG_FILE}.bak"
        killall xray 2>/dev/null
        sleep 1
        if pidof xray >/dev/null 2>&1; then
            killall -9 xray 2>/dev/null
            sleep 1
        fi
        if pidof xray >/dev/null 2>&1; then
            echo '{"status":"error","message":"Не удалось остановить Xray."}'
        else
            echo '{"status":"success","message":"Xray остановлен."}'
        fi
        exit 0
    elif [ "$ACTION" = "start" ]; then
        [ -f "${WATCHDOG_FILE}.bak" ] && mv "${WATCHDOG_FILE}.bak" "$WATCHDOG_FILE"
        if ! "$XRAY_BIN" -test -c "$XRAY_CONF" >/dev/null 2>&1; then
            echo '{"status":"error","message":"Конфиг битый — Xray не запущен."}'
            exit 0
        fi
        export GOGC=20; export GOMEMLIMIT=50MiB
        start-stop-daemon -S -b -x "$XRAY_BIN" -- -c "$XRAY_CONF"
        sleep 1
        if pidof xray >/dev/null 2>&1; then
            echo '{"status":"success","message":"Xray запущен."}'
        else
            echo '{"status":"error","message":"Xray не запустился."}'
        fi
        exit 0
    fi

    NEW_SUB_URL=$(printf '%s' "$POST_DATA" | tr '&' '\n' | grep '^SUB_URL=' | head -1 | cut -d= -f2- | url_decode)
    NEW_VLESS_URL=$(printf '%s' "$POST_DATA" | tr '&' '\n' | grep '^VLESS_URL=' | head -1 | cut -d= -f2- | url_decode)

    if [ -n "$NEW_SUB_URL" ]; then
        ESC=$(printf '%s' "$NEW_SUB_URL" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')
        sed -i "s|^SUB_URL=.*|SUB_URL=\"$ESC\"|" "$CONFIG_FILE"
        sed -i 's|^DIRECT_URL=.*|DIRECT_URL=""|' "$CONFIG_FILE"
        MSG="Подписка сохранена."
    elif [ -n "$NEW_VLESS_URL" ]; then
        ESC=$(printf '%s' "$NEW_VLESS_URL" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')
        sed -i 's|^SUB_URL=.*|SUB_URL=""|' "$CONFIG_FILE"
        sed -i "s|^DIRECT_URL=.*|DIRECT_URL=\"$ESC\"|" "$CONFIG_FILE"
        MSG="VLESS-ссылка сохранена."
    else
        echo '{"status":"error","message":"Пустые данные."}'; exit 0
    fi

    /etc/xray-updater.sh >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "{\"status\":\"success\",\"message\":\"$MSG Готово! Служба перезапущена.\"}"
    else
        echo "{\"status\":\"error\",\"message\":\"$MSG Но служба не запустилась! Проверьте logread.\"}"
    fi
else
    if [ -f "$CONFIG_FILE" ]; then
        SUB_URL=$(grep '^SUB_URL=' "$CONFIG_FILE" | head -1 | cut -d= -f2- | tr -d '"')
        DIRECT_URL=$(grep '^DIRECT_URL=' "$CONFIG_FILE" | head -1 | cut -d= -f2- | tr -d '"')
        if pidof xray >/dev/null 2>&1; then XRAY_STATUS="running"; else XRAY_STATUS="stopped"; fi
        SUB_ESC=$(json_escape "$SUB_URL")
        DIR_ESC=$(json_escape "$DIRECT_URL")
        echo "{\"status\":\"success\",\"sub_url\":\"$SUB_ESC\",\"direct_url\":\"$DIR_ESC\",\"xray\":\"$XRAY_STATUS\"}"
    else
        echo '{"status":"error","message":"Файл конфигурации не найден."}'
    fi
fi