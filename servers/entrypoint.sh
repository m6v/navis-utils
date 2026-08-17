#!/bin/bash

TIMESHIFT_FILE="/etc/timeshift"
TIMESTAMP_FILE="/etc/timestamp"

# Настройка сети
echo "Configuring container network interface host0..."
# sleep 0.5
/sbin/ip addr add 10.0.0.254/24 dev host0 2>/dev/null
/sbin/ip link set dev host0 up 2>/dev/null

on_exit() {
    # Здесь нельзя использовать внешние утилиты, поэтому импользуем флаг %(...)T,
    # который умеет брать текущее Unix-время напрямую из памяти самого процесса
    printf -v timestamp '%(%s)T' -1
    echo "$timestamp" > /etc/timestamp
    sync
    exit 0
}
trap "on_exit" EXIT SIGTERM SIGINT

# Запуск веб-сервера для раздачи репозитория Astra Linux в виртуальные машины УТК-СЗИ
# в sources.list добавить deb http://10.0.0.254/alse/main 1.7_x86-84 contrib main non-free
echo "Starting HTTP repository server on port 80..."
python3 -m http.server --directory /srv/repo 80 &

# Запуск chronyd на переднем плане (-d) в фоне самого bash (&)
echo "Starting chronyd in debug mode with drift correction disabled..."
/usr/sbin/chronyd -d -x &

# Вычисление времени простоя контейнера с момента последнего запуска
downtime=0
if [ -f "$TIMESTAMP_FILE" ]; then
    downtime=$(( $(date +%s) - $(cat "$TIMESTAMP_FILE") ))
fi
echo "Container downtime since last launch is ${downtime}s"

# Изменение времени смещения на время простоя 
if [ -f "$TIMESHIFT_FILE" ]; then
    timeshift=$(cat "$TIMESHIFT_FILE")
    (( timeshift += downtime )) && echo $timeshift > "$TIMESHIFT_FILE"
else
    timeshift=0
fi
echo "Setting time offset to ${timeshift}s"

# Вычисление и установка смещенного времени
target_time=$(date -d "@$(($(date +%s) + timeshift))" +"%Y-%m-%dT%H:%M:%S")
echo "Setting offset time to ${target_time}"
chronyc -a settime $target_time 

# Удержание контейнера в запущенном состоянии
wait
