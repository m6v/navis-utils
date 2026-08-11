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

        # Считываем сохраненное виртуальное время из конфига
        TARGET_TIME=$(cat "$CONF" | tr -d '[:space:]')
        echo "Запуск TimeMachine контейнера. Целевое виртуальное время: $TARGET_TIME"
        
        # Запускаем контейнер и передаем ему timestamp аргументом
        exec systemd-nspawn -D "$MERGED_DIR" -M "$CONTAINER_NAME" \
            --keep-unit --register=no \
            /entrypoint.sh "$TARGET_TIME"
        ;;

    stop)
        echo "TimeMachine: фиксируем виртуальное время..."

        if [ -f "$CONF" ]; then
            START_TIME=$(cat "$CONF" | tr -d '[:space:]')
            
            # Находим PID процесса sleep infinity
            SLEEP_PID=$(pgrep -f "sleep infinity")
            
            if [ -n "$SLEEP_PID" ]; then
                # 1. Получаем общий аптайм хоста с момента включения
                HOST_UPTIME=$(awk '{print int($1)}' /proc/uptime)
                
                # 2. Получаем секунду старта процесса с момента включения хоста
                PROCESS_START=$(awk '{print int($22 / cv)}' cv=$(getconf CLK_TCK) /proc/$SLEEP_PID/stat 2>/dev/null)
                
                # 3. Настоящий аптайм процесса — это их РАЗНИЦА!
                if [ -n "$HOST_UPTIME" ] && [ -n "$PROCESS_START" ]; then
                    UPTIME_SEC=$((HOST_UPTIME - PROCESS_START))
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
esac
