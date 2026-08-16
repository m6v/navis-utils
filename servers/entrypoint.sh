#!/bin/bash

# Обязательно должен пробрасываться с хоста в контейнер
TIMESHIFT_FILE="/etc/timeshift"
TIMESTAMP_FILE="/etc/timestamp"

# Настройка сети
echo "Настройка сетевого интерфейса host0 контейнера..."
sleep 0.5
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
echo "Запуск веб-сервера репозитория на порту 80..."
python3 -m http.server --directory /srv/repo 80 &

# Запуск chronyd на переднем плане (-d) в фоне самого bash (&)
echo "Запуск chronyd..."
/usr/sbin/chronyd -d -x &

# Вычисление времени простоя контейнера с момента последнего запуска
downtime=0
if [ -f "$TIMESTAMP_FILE" ]; then
    downtime=$(( $(date +%s) - $(cat "$TIMESTAMP_FILE") ))
fi
echo "Время простоя контейнера $downtime сек"

# Изменение времени смещения на время простоя 
if [ -f "$TIMESHIFT_FILE" ]; then
    timeshift=$(cat "$TIMESHIFT_FILE")
    (( timeshift += downtime )) && echo $timeshift > "$TIMESHIFT_FILE"
else
    timeshift=0
fi
echo "Смещение времени $timeshift сек"

# Вычисление и установка смещенного времени
shited_time=$(date -d "@$(($(date +%s) + timeshift))" +"%Y-%m-%dT%H:%M:%S")
echo "Установка смещенного времени $shited_time"
chronyc -a settime $shited_time 
echo "Установка запрета корректировки дрейфа часов"
chronyc -a manual delete 0

# Удержание контейнера в запущенном состоянии
wait
