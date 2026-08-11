## Итоговое дерево каталогов и файлов на хосте
/
├── etc/
│   ├── timemachine.conf                  # Точка сохранения времени (Unix Timestamp)
│   └── systemd/
│       ├── nspawn/
│       │   └── ntp-container.nspawn      # Сетевой конфиг nspawn (мост virbr0)
│       └── system/
│           └── timemachine.service       # Главный юнит-файл службы для systemd
│
├── usr/
│   └── local/
│       └── bin/
│           └── timemachine.sh            # Главный управляющий скрипт (start/stop)
│
└── var/
    └── lib/
        └── machines/
            └── ntp-container/            # Корневая папка проекта контейнера
                ├── lower/                # (Не используется, нижним слоем взят / хоста)
                ├── work/                 # Служебная директория для работы overlayfs
                ├── merged/               # Точка монтирования overlay (сюда смотрит nspawn)
                │   └── entrypoint.sh     # Ссылка на файл (виден внутри контейнера)
                └── upper/                # ВЕРХНИЙ СЛОЙ (все изменения контейнера)
                    ├── entrypoint.sh     # Скрипт инициализации сети и запуска Chrony
                    └── etc/
                        └── chrony/
                            └── chrony.conf # Изолированный конфиг Chrony для 10.0.0.254

## Краткая шпаргалка по содержимому ключевых файлов
/etc/timemachine.conf — Содержит только одно число (например, 1577836800). Это виртуальное время в секундах, которое считывается при старте и обновляется при остановке.
/etc/systemd/nspawn/ntp-container.nspawn — Связывает контейнер с мостом virbr0 и фиксирует имя интерфейса.
/usr/local/bin/timemachine.sh — Скрипт хоста. При start рассчитывает параметры и запускает systemd-nspawn. При stop — вычисляет, сколько секунд прожил процесс контейнера, прибавляет их к конфигу и тушит контейнер.
/var/lib/machines/ntp-container/upper/entrypoint.sh — Внутренний скрипт контейнера. Назначает IP 10.0.0.254 интерфейсу host0, запускает chronyd -d -x и через chronyc settime сдвигает время назад.
/var/lib/machines/ntp-container/upper/etc/chrony/chrony.conf — Конфиг Chrony внутри контейнера. Включает режим manual, local stratum 10, открывает доступ для сети 10.0.0.0/24 и делает привязку к bindaddress 10.0.0.254.

## Главные команды для управления
Запуск: sudo systemctl start timemachine
Остановка (с сохранением времени): sudo systemctl stop timemachine
Проверка статуса: sudo systemctl status timemachine
Проверка точного времени внутри Chrony: 
CHRONY_PID=$(pgrep -f "chronyd -d -x") && sudo nsenter -t $CHRONY_PID -m -n /usr/bin/chronyc tracking
