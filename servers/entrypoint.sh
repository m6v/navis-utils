#!/bin/bash

# Обязательно должен пробрасываться с хоста в контейнер
TIMESHIFT_FILE="/etc/timeshift"

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

downtime=$(( $(date +%s) - $(cat /etc/timestamp 2>/dev/null || echo 0) ))
echo "Время простоя контейнера $downtime сек"

# Уменьшение смещения в /etc/timeshift на время простоя 
if [ -f "$TIMESHIFT_FILE" ]; then
    echo $(( $(cat "$TIMESHIFT_FILE") + $downtime )) > "$TIMESHIFT_FILE"
fi

# TODO Дальше посчитать сумму смещения и текущего времени и передатьь ее в chrony


# Запуск веб-сервера для раздачи репозитория Astra Linux в виртуальные машины УТК-СЗИ
# в sources.list добавить deb http://10.0.0.254/alse/main 1.7_x86-84 contrib main non-free
echo "Запуск веб-сервера репозитория на порту 80..."
python3 -m http.server --directory /srv/repo 80 &

# Запуск chronyd на переднем плане (-d) в фоне самого bash (&)
echo "Запуск chronyd..."
/usr/sbin/chronyd -d -x &

# Проверка наличия и чтение файла со смещением времени
if [ -f "$TIMESHIFT_FILE" ]; then
    TIMESHIFT=$(cat "$TIMESHIFT_FILE")
    # Если файл пустой, установить нулевое смещение
    TIMESHIFT=${TIMESHIFT:-0}
else
    TIMESHIFT=0
fi

# Вычисление смещенного времени
SHIFTED_TIME=$(date -d "@$(($(date +%s) + TIMESHIFT))" +"%Y-%m-%dT%H:%M:%S")

# NB! Получается, что при каждом перезапуске мы смещаем время, а нужно единожды за сеанс ОС!
echo "Установка смещенного времени $SHIFTED_TIME"
chronyc -a settime $SHIFTED_TIME 
echo "Установка запрета корректировки дрейфа частов"
chronyc -a manual delete 0

# Удержание контейнера в запущенном состоянии
wait
