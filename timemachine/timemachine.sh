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

        TARGET_TIME=$(cat "$CONF" | tr -d '[:space:]')
        echo "Запуск TimeMachine контейнера. Виртуальное время: $TARGET_TIME"
        
        # --notify-ready=yes сообщает хосту о готовности (работает Type=notify)
        # --keep-unit УБРАН. Контейнер изолирован в cgroups, хост не заблокирован.
        exec systemd-nspawn --notify-ready=yes -M "$CONTAINER_NAME" -D "$MERGED_DIR" \
             /entrypoint.sh "$TARGET_TIME"
        ;;

    stop)
        echo "TimeMachine: фиксация виртуального времени..."

        if [ -f "$CONF" ]; then
            START_TIME=$(cat "$CONF" | tr -d '[:space:]')
            
            # Находим реальный PID процесса sleep внутри контейнера через machinectl
            # В режиме Type=notify/изолированной cgroup это работает безупречно
            LEADER_PID=$(machinectl show "$CONTAINER_NAME" -p Leader --value 2>/dev/null)
            
            if [ -n "$LEADER_PID" ] && [ "$LEADER_PID" -gt 0 ] 2>/dev/null; then
                SLEEP_PID=$(pgrep -P "$LEADER_PID" -f "sleep infinity")
                
                if [ -n "$SLEEP_PID" ]; then
                    HOST_UPTIME=$(awk '{print int($1)}' /proc/uptime)
                    PROCESS_START=$(awk '{print int($22 / cv)}' cv=$(getconf CLK_TCK) /proc/$SLEEP_PID/stat 2>/dev/null)
                    
                    if [ -n "$HOST_UPTIME" ] && [ -n "$PROCESS_START" ]; then
                        UPTIME_SEC=$((HOST_UPTIME - PROCESS_START))
                        VIRTUAL_TIME=$((START_TIME + UPTIME_SEC))
                    fi
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
        # Мягко тушим контейнер. С cgroup-изоляцией это чисто закроет ВСЕ процессы внутри.
        machinectl terminate "$CONTAINER_NAME" 2>/dev/null
        ;;
esac
