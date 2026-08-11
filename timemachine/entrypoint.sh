#!/bin/bash

TARGET_TIME="$1"

# 1. Настройка сетевого адреса внутри пространства имен контейнера
echo "TimeMachine: Настраиваем сетевой接口 host0..."
sleep 0.5
/sbin/ip addr add 10.0.0.254/24 dev host0 2>/dev/null
/sbin/ip link set dev host0 up 2>/dev/null

# 2. Формируем эталонный чистый конфиг для Chrony 4.x
cat << EOF > /etc/chrony/chrony.conf
manual
local stratum 10
allow 10.0.0.0/24
bindaddress 10.0.0.254
driftfile /var/lib/chrony/chrony.drift
EOF

# Переводим Timestamp обратно в текстовый календарный формат
TARGET_DATE=$(date -d "@$TARGET_TIME" +"%Y-%m-%d %H:%M:%S")

# 3. Запуск Chrony с флагом -x (категорический запрет на управление часами ядра)
echo "TimeMachine: Запускаем изолированный NTP-сервер..."
/usr/sbin/chronyd -d -x &
CHRONY_PID=$!

# Даем секунду на открытие локального сокета управления
sleep 1

echo "TimeMachine: Отматываем виртуальное время на $TARGET_DATE..."
# chronyc settime передает сдвиг виртуальной шкале Chrony, не меняя системную дату
chronyc -a "settime $TARGET_DATE"

# Держим контейнер активным, пока живет процесс хроника
wait $CHRONY_PID
