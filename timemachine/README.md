# Структура проекта

## Дерево каталогов и файлов на хосте
/
├── etc/
│   ├── faketime                            # точка сохранения времени (Unix Timestamp)
│   └── systemd/
│       ├── nspawn/
│       │   └── timemachine.nspawn          # сетевой конфиг nspawn (мост virbr0)
│       └── system/
│           └── timemachine.service         # главный юнит-файл службы для systemd
│
├── usr/
│   └── local/
│       └── bin/
│           └── timemachine.sh              # главный управляющий скрипт (start/stop)
│
└── var/
    └── lib/
        └── machines/
            └── timemachine/                # корневая папка проекта контейнера
                ├── work/                   # рабочая директория оверлея
                ├── merged/                 # директория монтирования оверлея
                └── upper/                  # директория верхнего слоя оверлея
                    ├── entrypoint.sh       # скрипт инициализации сети и запуска chrony
                    └── etc/
                        └── chrony/
                            └── chrony.conf # конфиг chrony

## Содержимое ключевых файлов
/etc/faketime — содержит Unix Timestamp (виртуальное время в секундах, которое считывается при старте и обновляется при остановке);
/etc/systemd/nspawn/timemachine.nspawn — связывает контейнер с мостом virbr0 и фиксирует имя интерфейса;
/usr/local/bin/timemachine.sh — скрипт хоста (при start рассчитывает параметры и запускает systemd-nspawn, при stop — вычисляет, сколько секунд прожил процесс контейнера, прибавляет их к конфигу и тушит контейнер);
/var/lib/machines/timemachine/upper/entrypoint.sh — скрипт контейнера (назначает IP 10.0.0.254 интерфейсу host0, запускает chronyd -d -x и через chronyc settime сдвигает время назад);
/var/lib/machines/timemachine/upper/etc/chrony/chrony.conf — конфиг chrony внутри контейнера (включает режим manual, local stratum 10, открывает доступ для сети 10.0.0.0/24 и делает привязку к bindaddress 10.0.0.254).

## Установка chrony
```bash
sudo -i
make install
mount -t overlay overlay -o lowerdir=/,upperdir=/var/lib/machines/timemachine/upper,workdir=/var/lib/machines/timemachine/work /var/lib/machines/timemachine/merged
systemd-nspawn -M timemachine --keep-unit --register=no -D /var/lib/machines/timemachine/merged /usr/bin/sleep infinity
# В другой консоли выполнить вход в контейнер
nsenter --target $(machinectl show timemachine -p Leader --value) --mount --uts --ipc --pid /bin/sh
# Внутри контейнера
apt install chrony
# На запрос действия с измененным файлом настройки chrony.conf выбрать "сохранить измененную локальную версию"
exit
# В консоли с запущенным контейнером завершить работу, троекратным ^]
umount /var/lib/machines/timemachine/merged
```

