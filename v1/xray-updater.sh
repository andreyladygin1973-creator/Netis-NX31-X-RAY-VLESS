#!/bin/sh
SUB_URL=""
DIRECT_URL=""
TEMPLATE="/etc/xray/config.template.json"
TARGET="/etc/xray/config.json"
TMP_SUB="/tmp/xray_sub.txt"
TMP_JSON="/tmp/xray_new_config.json"
LOG_TAG="xray-updater"

if [ -n "$DIRECT_URL" ]; then
    URI="$DIRECT_URL"
else
    if [ -z "$SUB_URL" ]; then
        logger -t "$LOG_TAG" "Ошибка: не задана ссылка"
        exit 1
    fi
    if ! wget --no-check-certificate -T 10 -q -O "$TMP_SUB" "$SUB_URL"; then
        logger -t "$LOG_TAG" "Ошибка: не удалось скачать подписку"
        exit 1
    fi
    URI=$(base64 -d "$TMP_SUB" 2>/dev/null | head -n 1 | tr -d '\r')
fi

if [ -z "$URI" ]; then
    logger -t "$LOG_TAG" "Ошибка: пустая ссылка"
    exit 1
fi

URI=$(echo "$URI" | sed 's/%3A/:/g; s/%2F/\//g; s/%3F/?/g; s/%3D/=/g; s/%26/\&/g; s/%20/ /g; s/%2B/+/g; s/%40/@/g; s/%23/#/g; s/%25/%/g; s/%5B/[/g; s/%5D/]/g')

case "$URI" in
    vless://*) ;;
    *) logger -t "$LOG_TAG" "Ошибка: не vless-ссылка"; exit 1 ;;
esac

URI_NO_PREFIX="${URI#vless://}"
URI_MAIN="${URI_NO_PREFIX%%#*}"
USERINFO="${URI_MAIN%%@*}"
HOSTPARAMS="${URI_MAIN#*@}"

case "$HOSTPARAMS" in
    *\?*)
        HOSTPORT="${HOSTPARAMS%%\?*}"
        PARAMS="${HOSTPARAMS#*\?}"
        ;;
    *)
        HOSTPORT="$HOSTPARAMS"
        PARAMS=""
        ;;
esac

UUID="${USERINFO%%:*}"
FLOW_USER=""
[ "$USERINFO" != "$UUID" ] && FLOW_USER="${USERINFO#*:}"

case "$HOSTPORT" in
    \[*\]:*)
        IP=$(echo "$HOSTPORT" | sed 's/^\[\(.*\)\]:.*/\1/')
        PORT=$(echo "$HOSTPORT" | sed 's/.*\]://')
        ;;
    *:*)
        IP="${HOSTPORT%%:*}"
        PORT="${HOSTPORT#*:}"
        ;;
    *)
        logger -t "$LOG_TAG" "Ошибка: не могу определить порт"
        exit 1
        ;;
esac

get_param() {
    KEY="$1"
    echo "$PARAMS" | tr '&' '\n' | grep "^${KEY}=" | head -n 1 | cut -d'=' -f2-
}

SECURITY=$(get_param security)
TYPE=$(get_param type)
SNI=$(get_param sni)
FP=$(get_param fp)
PBK=$(get_param pbk)
SID=$(get_param sid)
SPX=$(get_param spx)
FLOW_PARAM=$(get_param flow)
WS_HOST=$(get_param host)
WS_PATH=$(get_param path)
GRPC_SVC=$(get_param serviceName)
HEADER_TYPE=$(get_param headerType)

[ -z "$SECURITY" ] && SECURITY="none"
[ -z "$TYPE" ] && TYPE="tcp"
[ -z "$FP" ] && FP="chrome"
[ -z "$WS_PATH" ] && WS_PATH="/"

[ -z "$SPX" ] && SPX="/"
case "$SPX" in
    /*) ;;
    *) SPX="/$SPX" ;;
esac

FLOW=""
[ -n "$FLOW_PARAM" ] && FLOW="$FLOW_PARAM"
[ -z "$FLOW" ] && [ -n "$FLOW_USER" ] && FLOW="$FLOW_USER"

case "$SECURITY" in
    reality)
        STREAM_SS='"security": "reality", "realitySettings": {"serverName": "'"$SNI"'", "fingerprint": "'"$FP"'", "publicKey": "'"$PBK"'", "shortId": "'"$SID"'", "spiderX": "'"$SPX"'"}'
        ;;
    tls)
        STREAM_SS='"security": "tls", "tlsSettings": {"serverName": "'"$SNI"'", "fingerprint": "'"$FP"'"}'
        ;;
    *)
        STREAM_SS='"security": "none"'
        ;;
esac

case "$TYPE" in
    ws)
        if [ -n "$WS_HOST" ]; then
            WS_CFG='"wsSettings": {"path": "'"$WS_PATH"'", "headers": {"Host": "'"$WS_HOST"'"}}'
        else
            WS_CFG='"wsSettings": {"path": "'"$WS_PATH"'"}'
        fi
        STREAM_NET='"network": "ws", '"$WS_CFG"
        ;;
    grpc)
        STREAM_NET='"network": "grpc", "grpcSettings": {"serviceName": "'"$GRPC_SVC"'"}'
        ;;
    tcp)
        if [ -n "$HEADER_TYPE" ] && [ "$HEADER_TYPE" != "none" ]; then
            STREAM_NET='"network": "tcp", "tcpSettings": {"header": {"type": "'"$HEADER_TYPE"'"}}'
        else
            STREAM_NET='"network": "tcp"'
        fi
        ;;
    *)
        STREAM_NET='"network": "'"$TYPE"'"'
        ;;
esac

OUTBOUND='{"protocol": "vless", "settings": {"vnext": [{"address": "'"$IP"'", "port": '"$PORT"', "users": [{"id": "'"$UUID"'", "encryption": "none", "flow": "'"$FLOW"'"}]}]}, "streamSettings": {'"$STREAM_NET"', '"$STREAM_SS"'}, "tag": "proxy"}'
OUTBOUND=$(echo "$OUTBOUND" | tr -d '\n')

sed "s|\"__OUTBOUND_PLACEHOLDER__\"|$OUTBOUND|" "$TEMPLATE" > "$TMP_JSON"

TEST_OUT=$(/tmp/xray -test -c "$TMP_JSON" 2>&1)
if [ $? -ne 0 ]; then
    logger -t "$LOG_TAG" "Ошибка конфига: $TEST_OUT"
    exit 1
fi

if cmp -s "$TMP_JSON" "$TARGET"; then exit 0; fi

cp "$TMP_JSON" "$TARGET"
killall xray 2>/dev/null
sleep 1
export GOGC=20
export GOMEMLIMIT=50MiB
start-stop-daemon -S -b -x /tmp/xray -- -c "$TARGET"
logger -t "$LOG_TAG" "Конфиг обновлён, Xray перезапущен"
exit 0