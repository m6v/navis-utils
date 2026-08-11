#!/bin/bash

TARGET_TIME="$1"

# 1. Настройка сетевого адреса внутри пространства имен контейнера
echo "TimeMachine: Настраиваем сетевой интерфейс host0..."
sleep 0.5
/sbin/ip addr add 10.0.0.254/24 dev host0 2>/dev/null
/sbin/ip link set dev host0 up 2>/dev/null

TARGET_DATE=$(date -d "@$TARGET_TIME" +"%Y-%m-%d %H:%M:%S")

# 2. Запуск Chrony с флагом -x и -U (брать готовый сокет, предоставленный системой)
echo "TimeMachine: Запускаем изолированный NTP-сервер..."
/usr/sbin/chronyd -d -x -U &

# 3. Мгновенный перевод времени (сокет уже гарантированно существует)
echo "TimeMachine: Отматываем виртуальное время на $TARGET_DATE..."
chronyc -a "settime $TARGET_DATE"

# 4. Переводим контейнер в режим бесконечного удержания сети и процессов
echo "TimeMachine: Контейнер успешно переведен в режим infinity."
exec /bin/sleep infinity
