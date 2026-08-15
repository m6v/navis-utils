# Структура проекта

## Дерево каталогов и файлов на хосте
```
/
├── etc/
│   ├── timeshift                           # Точка сохранения смещения времени
│   └── systemd/
│       ├── nspawn/
│       │   └── timemachine.nspawn          # Сетевой конфиг nspawn (мост virbr0)
│       └── system/
│           └── timemachine.service         # Юнит-файл службы для systemd
├── run/
│   └── timemachine.stamp                   # Флаг смещения времени в текущем сеансе ОС 
│
├── usr/
│   └── local/
│       └── bin/
│           └── timemachine.py              # Управляющий скрипт
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
- `/etc/timeshift` — содержит смещение в секундах которое нужно прибавлять к текущему времени и отдавать клиентам.  (вычисляется при старте контейнера путем добавления времени простоя в выключенном состоянии);
- `/etc/systemd/nspawn/timemachine.nspawn` — связывает контейнер с мостом `virbr0` и фиксирует имя интерфейса;
- `/usr/local/bin/timemachine.sh` — скрипт хоста который добавляет к смещению времени время простоя хоста;
- `/var/lib/machines/timemachine/upper/entrypoint.sh` — скрипт контейнера (назначает IP 10.0.0.254 интерфейсу `host0`, запускает `chronyd -d -x` и через `chronyc settime` устанавливает время в соответствии с faketime);
- `/var/lib/machines/timemachine/upper/etc/chrony/chrony.conf` — конфиг chrony внутри контейнера (включает режим `manual`, `local stratum 10`, открывает доступ для сети 10.0.0.0/24 и делает привязку к bindaddress 10.0.0.254).

## Проверка настроек сети

> Если сетевое взаимодействие контейнера с хостом и клиентами отсутствует, нужно проверить к какому мосту подключен интерфейс контейнера `vb-timemachine`
Пример, когда вместо моста `virbr0` интерфейс подключился к мосту `br0`
```
7: vb-timemachine@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br0 state UP group default qlen 1000
    link/ether 6a:ef:48:dc:74:8b brd ff:ff:ff:ff:ff:ff link-netnsid 0
```
Это происходит из-за настроек `systemd-neyworkd`. В данном случае в `/etc/systemd/network` есть файл с конфигом настройки, в соответствии с которым все интерфейсы, с именем, удовлетворяющем шаблону `v[eb]-*`, подключаются к мосту `br0`
```
[Match]
Name=v[eb]-*
[Network]
Bridge=br0
```
Чтобы исправить ситуацию, нужно добавить в секцию `[Match]` параметр `Name=!vb-timemachine`, перезагрузить службы `systemd-neyworkd` и `timemachine`
Теперь видим, что интерфейс контейнера `vb-timemachine` подключен к мосту `virbr0`
```
9: vb-timemachine@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master virbr0 state UP group default qlen 1000
    link/ether 6a:ef:48:dc:74:8b brd ff:ff:ff:ff:ff:ff link-netnsid 0
```

## Установка сервера времени
```bash
sudo -i
# Установка контейнера
make install
# Вход в контейнер
nsenter --target $(machinectl show timemachine -p Leader --value) --mount --net --uts --ipc --pid /bin/bash
# Действия внутри контейнера
apt install chrony
# На запрос действия с измененным файлом настройки chrony.conf выбрать "сохранить измененную локальную версию"
exit
```

## Проверка состояния службы
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

### Настройка конфигурации
```
sudo -i
apt unstall chrony

CONF_PATH="/etc/chrony/chrony.conf"

# Резервное копирование chrony.conf
cp "$CONF_PATH" "${CONF_PATH}.bak"

# Отключаение дефолтных серверовы и пулов
sed -i 's/^\s*\(server.*\)/# \1/' "$CONF_PATH"
sed -i 's/^\s*\(pool.*\)/# \1/' "$CONF_PATH"

# Разрешение безлимитного прыжка времени назад
if grep -q "makestep" "$CONF_PATH"; then
    sed -i 's/^\s*makestep.*/makestep 1 -1/' "$CONF_PATH"
else
    echo "makestep 1 -1" >> "$CONF_PATH"
fi

# Добавление сервера времени
echo "server 10.0.0.254 prefer iburst" >> "$CONF_PATH"

systemctl restart chrony
```

## Принудительное обновление времени
```
chronyc -a makestep
```
