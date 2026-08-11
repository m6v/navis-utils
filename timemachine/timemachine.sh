#!/bin/bash

CONF="/etc/timemachine.conf"
CONTAINER_NAME="ntp-container"
MERGED_DIR="/var/lib/machines/ntp-container/merged"

case "$1" in
    start)
        if [ ! -f "$CONF" ]; then
            echo "Ошибка: Конфиг $CONF не найден!"
            exit 1
        fi

        TARGET_TIME=$(cat "$CONF" | tr -d '[:space:]')
        echo "Запуск TimeMachine контейнера. Целевое виртуальное время: $TARGET_TIME"
        
        exec systemd-nspawn -D "$MERGED_DIR" -M "$CONTAINER_NAME" \
            --keep-unit --register=no \
            /entrypoint.sh "$TARGET_TIME"
        ;;

    stop)
        echo "TimeMachine: фиксируем виртуальное время..."

        if [ -f "$CONF" ]; then
            START_TIME=$(cat "$CONF" | tr -d '[:space:]')
            
            # Ищем PID главного процесса-удержания sleep infinity на хосте
            SLEEP_PID=$(pgrep -f "sleep infinity")
            
            if [ -n "$SLEEP_PID" ]; then
                # Считаем точный аптайм контейнера напрямую через тики ядра хоста
                UPTIME_SEC=$(awk '{print int($22 / cv)}' cv=$(getconf CLK_TCK) /proc/$SLEEP_PID/stat 2>/dev/null)
                
                if [ -n "$UPTIME_SEC" ] && [ "$UPTIME_SEC" -gt 0 ]; then
                    VIRTUAL_TIME=$((START_TIME + UPTIME_SEC))
                fi
            fi
        fi

        if [ -n "$VIRTUAL_TIME" ] && [[ "$VIRTUAL_TIME" =~ ^[0-9]+$ ]]; then
            echo "$VIRTUAL_TIME" > "$CONF"
            echo "Время успешно заморожено в $CONF: $VIRTUAL_TIME"
        else
            echo "Предупреждение: Не удалось рассчитать аптайм, конфиг не изменен."
        fi

        echo "Останавливаем контейнер..."
        machinectl terminate "$CONTAINER_NAME" 2>/dev/null
        ;;

    *)
        echo "Использование: $0 {start|stop}"
        exit 1
        ;;
esac
