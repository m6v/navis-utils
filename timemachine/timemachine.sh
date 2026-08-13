#!/bin/bash

CONF="/etc/faketime"
CONTAINER_NAME="timemachine"
MERGED_DIR="/var/lib/machines/timemachine/merged"

case "$1" in
    start)
        if [ ! -f "$CONF" ]; then
            echo "Ошибка: Конфиг $CONF не найден!"
            exit 1
        fi

        # Чтение виртуального времени из конфига
        TARGET_TIME=$(cat "$CONF" | tr -d '[:space:]')
        echo "Запуск TimeMachine контейнера. Виртуальное время: $TARGET_TIME"
        
        # Запускаем контейнер и передаем ему timestamp аргументом
        exec systemd-nspawn --keep-unit  -M "$CONTAINER_NAME" \
             -D "$MERGED_DIR" /entrypoint.sh "$TARGET_TIME"
        ;;

    stop)
        echo "TimeMachine: фиксация виртуального времени..."

        if [ -f "$CONF" ]; then
            START_TIME=$(cat "$CONF" | tr -d '[:space:]')
            
            # Поиск PID процесса sleep infinity
            SLEEP_PID=$(pgrep -f "sleep infinity")
            
            if [ -n "$SLEEP_PID" ]; then
                # Получение общего аптайма хоста с момента включения
                HOST_UPTIME=$(awk '{print int($1)}' /proc/uptime)
                
                # Получение секунды старта процесса с момента включения хоста
                PROCESS_START=$(awk '{print int($22 / cv)}' cv=$(getconf CLK_TCK) /proc/$SLEEP_PID/stat 2>/dev/null)
                
                # Вычисление истинного аптайма процесса как разности
                # между аптайма хоста и старта процесса с момента включения хоста
                if [ -n "$HOST_UPTIME" ] && [ -n "$PROCESS_START" ]; then
                    UPTIME_SEC=$((HOST_UPTIME - PROCESS_START))
                    VIRTUAL_TIME=$((START_TIME + UPTIME_SEC))
                fi
            fi
        fi

        if [ -n "$VIRTUAL_TIME" ] && [[ "$VIRTUAL_TIME" =~ ^[0-9]+$ ]]; then
            echo "$VIRTUAL_TIME" > "$CONF"
            echo "Время успешно сохранено в $CONF: $VIRTUAL_TIME"
        else
            echo "Предупреждение: Не удалось рассчитать аптайм, конфиг не изменен."
        fi

        echo "Остановка контейнера..."
        machinectl terminate "$CONTAINER_NAME" 2>/dev/null
        ;;
esac
