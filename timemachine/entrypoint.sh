#!/bin/bash

TARGET_TIME="$1"

# 1. Настройка сети
echo "TimeMachine: Настраиваем сетевой интерфейс host0..."
sleep 0.5
/sbin/ip addr add 10.0.0.254/24 dev host0 2>/dev/null
/sbin/ip link set dev host0 up 2>/dev/null

TARGET_DATE=$(date -d "@$TARGET_TIME" +"%Y-%m-%d %H:%M:%S")

# 2. Запуск Chrony на переднем плане (-d) в фоне самого bash (&)
echo "TimeMachine: Запускаем изолированный NTP-сервер..."
/usr/sbin/chronyd -d -x &

# 3. Перевод времени (Chrony на переднем плане открывает сокет мгновенно)
echo "TimeMachine: Отматываем виртуальное время на $TARGET_DATE..."
sleep 1
chronyc -a "settime $TARGET_DATE" 2>/dev/null

# 4. Удержание контейнера каркасом sleep infinity
echo "TimeMachine: Контейнер переведен в режим infinity."
exec /bin/sleep infinity
