#!/usr/bin/env python3

import logging
import os
import subprocess
import sys
import time
from datetime import datetime

# Настройка путей
TIMESHIFT_FILE = "/etc/timeshift"
STAMP_FILE = "/run/timeshifter.stamp"

# Настройка конфигурации логирования
logging.basicConfig(
    level=logging.INFO,
    format='[%(levelname)s] %(message)s'
)


def get_event_timestamp(event_type, timeshift_file_path=TIMESHIFT_FILE):
    """Возвращает Unix Timestamp старта текущей сессии или завершения предыдущей.

    event_type =  0: Время включения (читается аппаратно из /proc/stat)
    event_type = -1: Время выключения (Способ А: journalctl -> Способ Б: mtime файла)
    """

    if event_type == 0:
        # Вычисление времени включения по /proc/stat
        try:
            with open("/proc/stat", "r") as f:
                for line in f:
                    if line.startswith("btime"):
                        return int(line.split()[1])
            logging.error("Маркер btime не найден в /proc/stat")
            return None
        except Exception as e:
            logging.error(f"Не удалось прочитать /proc/stat: {e}")
            return None

    try:
        # Вычисление времени выключения по журналу journalctl
        result = subprocess.run(
            [
                "journalctl",
                "-b",
                "-1",
                "-n",
                "1",
                "--output=short-unix",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )

        lines = result.stdout.strip().split("\n")
        if lines and lines[0]:
            event_timestamp = int(lines[0].split(".")[0])
            return event_timestamp

        return None

    except (subprocess.CalledProcessError, ValueError, IndexError) as e:
        logging.warning(e)

    # Вычисление времени выключения по mtime файла со смещением
    if timeshift_file_path and os.path.exists(timeshift_file_path):
        return int(os.path.getmtime(timeshift_file_path))

    return None


def main():
    # Защита от повторного запуска в рамках одной сессии ОС
    if os.path.exists(STAMP_FILE):
        logging.info("Корректировка уже выполнялась в этой сессии.")
        sys.exit(0)

    # Проверка наличия файла со смещением времени
    if not os.path.exists(TIMESHIFT_FILE):
        logging.error(f"Файл {TIMESHIFT_FILE} со смещением времени не найден.")
        sys.exit(1)

    # Получение времени включения машины
    boot_time = get_event_timestamp(0)
    if boot_time is None:
        logging.critical("Не удалось определить время включения.")
        sys.exit(1)

    # Получение времени выключения (использует TIMESHIFT_FILE по умолчанию)
    shutdown_time = get_event_timestamp(-1)
    if shutdown_time is None:
        logging.critical("Не удалось определить время выключения.")
        sys.exit(1)

    # Проверка условий и расчет downtime
    if boot_time > shutdown_time:
        downtime = boot_time - shutdown_time
        logging.info(f"Первый запуск после загрузки. Расчетный downtime: {downtime} сек.")
    else:
        logging.critical("Время выключения новее времени включения машины.")
        sys.exit(1)

    # Корректировка файла со смещением времени
    try:
        with open(TIMESHIFT_FILE, "r") as f:
            content = f.read().strip()
            if not content:
                logging.error(f"Файл {TIMESHIFT_FILE} пуст.")
                sys.exit(1)
            current_shift = int(content)

        # Вычисление нового смещения
        new_shift = current_shift - downtime

        with open(TIMESHIFT_FILE, "w") as f:
            f.write(str(new_shift) + "\n")
        logging.info(f"Смещение успешно обновлено с {current_shift} на {new_shift}")

        # Создание флаг-файла для блокирования повторных запусков в одной сессии ОС
        with open(STAMP_FILE, "w") as f:
            f.write(f"Timeshift corrected at {datetime.now().strftime('%d.%m.%Y %H:%M:%S')}\n")
        logging.info(f"Создан маркер сессии: {STAMP_FILE}")

        # Расчет виртуального времени программы для контроля в логах
        current_time = int(time.time())
        virtual_timestamp = current_time + new_shift
        virtual_date_str = datetime.fromtimestamp(virtual_timestamp).strftime('%d.%m.%Y %H:%M:%S')
        
        logging.info(f"Текущее Unix-время: {current_time}")
        logging.info(f"Расчетное время программы в Unix: {virtual_timestamp}")
        logging.info(f"Расчетное время программы (дата): {virtual_date_str}")

    except ValueError:
        logging.error(f"Ошибка: содержимое файла {TIMESHIFT_FILE} не является числом.")
        sys.exit(1)
    except IOError as e:
        logging.error(f"Ошибка ввода-вывода при изменении файлов: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
