# Реализация веб-панели инструктора УТК-СЗИ для доступа к интерфейсам виртуальных машин обучаемых с помощью novnc

Настройки
1 Установить novnc на АРМ инструктора (требуется подключить base- и extended-репозитории)
2 Файл tokens скопировать в каталог /etc/novnc АРМ инструктора
3 В настройках виртуальных машин установить тип дисплея VNC, адрес "Все интерфейсы" и порт для подключения (в соответствии с фойлом tokens)

TODO
- сделать юнит для автоматического запуска серверной части;
- по возможности упростить обработку файла tokens, сейчас слишком сложно

# Юнит запуска контейнера systemd-nspawn

```bash
cat << EOF > /etc/systemd/system/novnc-container.service
[Unit]
Description=noVNC systemd-nspawn Container with OverlayFS
After=network.target

[Service]
Type=simple
# Принудительно очищаем точку монтирования, если не была размонтирована
ExecStartPre=-/usr/bin/umount -l /var/lib/novnc/merged
# Создаем папки перед запуском, если они отсутствуют
ExecStartPre=/usr/bin/mkdir -p /var/lib/novnc/upper /var/lib/novnc/work /var/lib/novnc/merged
# Монтируем OverlayFS
ExecStartPre=/usr/bin/mount -t overlay overlay -o lowerdir=/,upperdir=/var/lib/novnc/upper,workdir=/var/lib/novnc/work /var/lib/novnc/merged

# Запуск контейнера (флаг --keep-unit связывает процессы внутри), флан -M задает имя контейнера для последующего подключения с помощью `machinectl shell novnc`
# Запуск /bin/sleep infinity "замораживает" контейнер в запущенном состоянии для последующего входа в него
# В итоговой редакции будем запускать службу websockify
ExecStart=/usr/bin/systemd-nspawn --keep-unit -M novnc -D /var/lib/novnc/merged /bin/sleep infinity

# Размонтирование OverlayFS
ExecStopPost=/usr/bin/umount -l /var/lib/novnc/merged
# Очистка рабочего каталога OverlayFS
ExecStopPost=/usr/bin/rm -rf /var/lib/novnc/work/work

KillMode=mixed
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now novnc-container
```

## Прямой вход через nsenter
```
nsenter -t $(machinectl show novnc -p Leader --value) -m -u -i -n -p /bin/bash
```
> Штатный способ входа с помощью `machinectl shell novnc` не работает, т.к. требует как минимум запуска dbus внутри контейнера, что явдяется излишним в данном случае

После входа в контейнер устанавливаем novnc и другие необходимые программы

