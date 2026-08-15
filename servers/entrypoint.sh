#!/bin/bash

TIMESHIFT_FILE="/etc/timeshift"

# Настройка сети
echo "TimeMachine: Настройка сетевого интерфейса host0 контейнера..."
sleep 0.5
/sbin/ip addr add 10.0.0.254/24 dev host0 2>/dev/null
/sbin/ip link set dev host0 up 2>/dev/null

# Запуск веб-сервера для раздачи репозитория Astra Linux в виртуальные машины УТК-СЗИ
# в sources.list добавить deb http://10.0.0.254/alse/main 1.7_x86-84 contrib main non-free
echo "Запуск веб-сервера репозитория на порту 80..."
python3 -m http.server --directory /srv/repo 80 &

# Запуск Chrony на переднем плане (-d) в фоне самого bash (&)
echo "Запуск изолированного Chronyd..."
/usr/sbin/chronyd -d -x &

# Проверка наличия и чтение файла со смещением времени
if [ -f "$TIMESHIFT_FILE" ]; then
    SHIFT=$(cat "$TIMESHIFT_FILE")
    # Если файл пустой, установить нулевое смещение
    SHIFT=${SHIFT:-0}
else
    SHIFT=0
fi

# Вычисление смещенного времени
SHIFTED_TIME=$(date -d "@$(($(date +%s) + SHIFT))" +"%Y-%m-%dT%H:%M:%S")

echo "Установка смещенного времени $SHIFTED_TIME"
chronyc -a settime $SHIFTED_TIME 
echo "Запрет корректировки дрейфа частов"
chronyc -a manual delete 0

# Удержание контейнера в запущенном состоянии
exec /bin/sleep infinity
