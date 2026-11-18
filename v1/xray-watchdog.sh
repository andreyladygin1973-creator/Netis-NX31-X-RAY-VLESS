#!/bin/sh
while true; do
    sleep 60
    if ! pidof xray > /dev/null; then
        logger -t xray-watchdog "Процесс Xray не найден. Перезапуск..."
        export GOGC=20
        export GOMEMLIMIT=80MiB
        start-stop-daemon -S -b -x /tmp/xray -- -c /etc/xray/config.json
        sleep 2
        if pidof xray > /dev/null; then
            logger -t xray-watchdog "Xray успешно перезапущен."
        else
            logger -t xray-watchdog "ОШИБКА: Не удалось запустить Xray!"
        fi
    fi
done