#!/usr/bin/env python3
import os
import sys
import subprocess
import time

CONF = "/etc/faketime"
CONTAINER_NAME = "timemachine"
MERGED_DIR = "/var/lib/machines/timemachine/merged"
VIRTUAL_BASE = 1765832400  # 15.01.2026 00:00:00

def get_root_device():
    """Поиск блочного устройства, примонтированного в корень ФС"""
    try:
        with open("/proc/mounts", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "/":
                    return parts[0]
    except Exception as e:
        print(f"Ошибка определения корневого диска: {e}", file=sys.stderr)
    return None

print(get_root_device())
sys.exit()

# Чтение конфигурации
real_now = int(time.time())
if not os.path.exists(CONF) or os.path.getsize(CONF) == 0:
    with open(CONF, "w") as f:
        f.write(f"{VIRTUAL_BASE}\n")

with open(CONF, "r") as f:
    last_virtual = int(f.read().strip().split()[0])

# Получение текущего аптайма хоста
with open("/proc/uptime", "r") as f:
    uptime = int(float(f.readline().split()[0]))

# Вычисление времени включения хоста
real_boot = real_now - uptime

# Чтение времени модификации файла (время прошлого старта контейнера)
try:
    real_file_mtime = int(os.path.getmtime(CONF))
except:
    real_file_mtime = real_now

# Вычисление простоя хоста в выключенном состоянии
downtime = 0
root_device = get_root_device()

if root_device and os.path.exists(root_device):
    try:
        # Получение даты последней записи на диск от ядра Linux
        cmd = f"tune2fs -l {root_device} | grep 'Last write time:'"
        raw_output = subprocess.check_output(cmd, shell=True).decode().strip()
        raw_date = raw_output.split(":", 1)[1].strip()
        
        # Конвертация строковой даты tune2fs в Unix timestamp
        real_last_write = int(subprocess.check_output(["date", "-d", raw_date, "+%s"]))
        
        # Расчет даунтайма хоста
        downtime = real_boot - real_last_write
        
        # Если простой небольщой, то это не выключение хоста, а перезагрузка
        if downtime < 10 or downtime > 100000000:
            downtime = 0
            
    except Exception as e:
        print(f"Предупреждение: Ошибка чтения tune2fs: {e}. Простой принят за 0.", file=sys.stderr)
else:
    print("Предупреждение: Системный раздел не определен. Простой принят за 0.", file=sys.stderr)

# Сколько всего реального времени прошло на Земле между двумя стартами контейнера
total_elapsed = real_now - real_file_mtime

if real_boot > real_file_mtime:
    # ИНТЕРВАЛ: ХОЛОДНЫЙ СТАРТ (Хост перезагружался с момента прошлой записи)
    # Вычитаем из общего прошедшего времени чистый простой ПК в шкафу
    target_time = last_virtual + total_elapsed - downtime
    print(f"TimeMachine: [Холодный старт]. Прошло времени: {total_elapsed}с, из них ПК спал: {downtime}с.")
else:
    # ИНТЕРВАЛ: ГОРЯЧИЙ РЕСТАРТ (Контейнер перезапустили на работающем хосте)
    # Никаких простоев диска вычитать не нужно, берем чистую дельту
    target_time = last_virtual + total_elapsed
    print(f"TimeMachine: [Рестарт контейнера]. Прошло времени: {total_elapsed}с.")

# Сохранение обновленного значения
with open(CONF, "w") as f:
    f.write(f"{target_time}\n")

print(f"TimeMachine: Итоговое виртуальное время: {target_time}")

# Замещение процесса на systemd-nspawn
args = [
    "/usr/bin/systemd-nspawn",
    "--keep-unit",
    "-M", CONTAINER_NAME,
    "-D", MERGED_DIR,
    "/entrypoint.sh", str(target_time)
]
os.execv(args[0], args)
