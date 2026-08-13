# Структура проекта

## Дерево каталогов и файлов на хосте
```
/
├── etc/
│   ├── faketime                            # Точка сохранения времени (Unix Timestamp)
│   └── systemd/
│       ├── nspawn/
│       │   └── timemachine.nspawn          # Сетевой конфиг nspawn (мост virbr0)
│       └── system/
│           └── timemachine.service         # Юнит-файл службы для systemd
│
├── usr/
│   └── local/
│       └── bin/
│           └── timemachine.sh              # Управляющий скрипт (start/stop)
│
└── var/
    └── lib/
        └── machines/
            └── timemachine/                # Корневая директория проекта контейнера
                ├── work/                   # Рабочая директория оверлея
                ├── merged/                 # Директория монтирования оверлея
                └── upper/                  # Директория верхнего слоя оверлея
                    ├── entrypoint.sh       # Скрипт инициализации сети и запуска chrony
                    └── etc/
                        └── chrony/
                            └── chrony.conf # Конфиг chrony
```
## Назначение файлов
- `/etc/faketime` — содержит Unix Timestamp (виртуальное время в секундах, которое считывается при старте и обновляется при остановке контейнера);
- `/etc/systemd/nspawn/timemachine.nspawn` — связывает контейнер с мостом `virbr0` и фиксирует имя интерфейса;
- `/usr/local/bin/timemachine.sh` — скрипт хоста (при аргументе `start` рассчитывает параметры и запускает `systemd-nspawn`, при `stop` — вычисляет, сколько секунд прожил процесс контейнера, прибавляет их к конфигу и останавливает контейнер);
- `/var/lib/machines/timemachine/upper/entrypoint.sh` — скрипт контейнера (назначает IP 10.0.0.254 интерфейсу `host0`, запускает `chronyd -d -x` и через `chronyc settime` устанавливает время в соответствии с faketime);
- `/var/lib/machines/timemachine/upper/etc/chrony/chrony.conf` — конфиг chrony внутри контейнера (включает режим `manual`, `local stratum 10`, открывает доступ для сети 10.0.0.0/24 и делает привязку к bindaddress 10.0.0.254).

## Установка
```bash
sudo -i
make install
mount -t overlay overlay -o lowerdir=/,upperdir=/var/lib/machines/timemachine/upper,workdir=/var/lib/machines/timemachine/work /var/lib/machines/timemachine/merged
systemd-nspawn -M timemachine --keep-unit --register=no -D /var/lib/machines/timemachine/merged /usr/bin/sleep infinity
# В другой консоли выполнить вход в контейнер
nsenter --target $(machinectl show timemachine -p Leader --value) --mount --net --uts --ipc --pid /bin/sh
# Внутри контейнера
apt install chrony
# На запрос действия с измененным файлом настройки chrony.conf выбрать "сохранить измененную локальную версию"
exit
# В консоли с запущенным контейнером завершить работу, троекратным ^]
umount /var/lib/machines/timemachine/merged
make restart
```

## Проверка состояния
```
sudo make status
● timemachine.service - NTP Service Container with TimeMachine
   Loaded: loaded (/etc/systemd/system/timemachine.service; disabled; vendor preset: enabled)
   Active: active (running) since Wed 2026-08-12 11:15:18 MSK; 43s ago
  Process: 12717 ExecStartPre=/usr/bin/mkdir -p /var/lib/machines/timemachine/upper /var/lib/machines/timemachine/work /var/lib/machines/timemachine/merged (code=exited, status=0/SUCCESS)
  Process: 12718 ExecStartPre=/usr/bin/mount -t overlay overlay -o lowerdir=/,upperdir=/var/lib/machines/timemachine/upper,workdir=/var/lib/machines/timemachine/work /var/lib/machines/timemachine/merged (code=exited, status=0/SUCCESS)
 Main PID: 12719 (systemd-nspawn)
    Tasks: 3 (limit: 4915)
   Memory: 2.4M
      CPU: 83ms
   CGroup: /system.slice/timemachine.service
           ├─payload
           │ ├─12725 /bin/sleep infinity
           │ └─12745 /usr/sbin/chronyd -d -x
           └─supervisor
             └─12719 systemd-nspawn -D /var/lib/machines/timemachine/merged -M timemachine --keep-unit --register=no /entrypoint.sh 1768434000

авг 12 11:15:18 hp-260 timemachine.sh[12719]: Host and machine ids are equal (497988e2e4874331a6359910e1b5f489): refusing to link journals
авг 12 11:15:18 hp-260 timemachine.sh[12719]: TimeMachine: Настройка сетевого интерфейса host0 контейнера...
авг 12 11:15:19 hp-260 timemachine.sh[12719]: TimeMachine: Запуск изолированного NTP-сервера...
авг 12 11:15:19 hp-260 timemachine.sh[12719]: TimeMachine: Установка виртуального времени на 2026-01-15 02:40:00...
авг 12 11:15:19 hp-260 timemachine.sh[12719]: 2026-08-12T08:15:19Z chronyd version 4.3 starting (+CMDMON +NTP +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +ASYNCDNS +NTS +SE… +IPV6 -DEBUG)
авг 12 11:15:19 hp-260 timemachine.sh[12719]: 2026-08-12T08:15:19Z Disabled control of system clock
авг 12 11:15:20 hp-260 timemachine.sh[12719]: 2026-08-12T08:15:20Z Making a slew of 18088520.042862
авг 12 11:15:20 hp-260 timemachine.sh[12719]: 2026-08-12T08:15:20Z System clock wrong by -18088520.042862 seconds
авг 12 11:15:20 hp-260 timemachine.sh[12719]: 200 OK
авг 12 11:15:20 hp-260 timemachine.sh[12719]: Clock was 18088520.00 seconds fast.  Frequency change = 0.00ppm, new frequency = 0.00ppm
Hint: Some lines were ellipsized, use -l to show in full.
```

## Настройка клиентов
```
sudo -i
apt unstall chrony

CONF_PATH="/etc/chrony/chrony.conf"

# Делаем резервную копию chrony.conf
cp "$CONF_PATH" "${CONF_PATH}.bak"

# Отключаем дефолтные серверы и пулы
sed -i 's/^\s*\(server.*\)/# \1/' "$CONF_PATH"
sed -i 's/^\s*\(pool.*\)/# \1/' "$CONF_PATH"

# Разрешаем безлимитный прыжок времени назад (makestep 1 -1)
if grep -q "makestep" "$CONF_PATH"; then
    sed -i 's/^\s*makestep.*/makestep 1 -1/' "$CONF_PATH"
else
    echo "makestep 1 -1" >> "$CONF_PATH"
fi

# Добавляем timemachine-сервер времени
echo "server 10.0.0.254 iburst" >> "$CONF_PATH"

systemctl restart chrony
```

Принудительное обновление времени
```
chronyc -a makestep
```
