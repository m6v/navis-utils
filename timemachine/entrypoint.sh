#!/bin/bash

TARGET_TIME="$1"

# Настройка сети
echo "TimeMachine: Настройка сетевого интерфейса host0 контейнера..."
sleep 0.5
/sbin/ip addr add 10.0.0.254/24 dev host0 2>/dev/null
/sbin/ip link set dev host0 up 2>/dev/null

TARGET_DATE=$(date -d "@$TARGET_TIME" +"%Y-%m-%d %H:%M:%S")

# Запуск Chrony на переднем плане (-d) в фоне самого bash (&)
echo "TimeMachine: Запуск изолированного NTP-сервера..."
/usr/sbin/chronyd -d -x &

# Перевод времени на $TARGET_DATE
echo "TimeMachine: Установка виртуального времени на $TARGET_DATE..."
sleep 1
chronyc -a "settime $TARGET_DATE" 2>/dev/null

# Удержание контейнера в запущенном состоянии
exec /bin/sleep infinity
