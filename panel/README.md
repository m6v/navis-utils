# Веб-панель инструктора УТК-СЗИ для доступа к интерфейсам виртуальных машин обучаемых с помощью novnc

## Установка novnc на АРМ инструктора
```
# Каталог со скачанными из base- и extended-репозиториями зависимостями novnc
cd dpkgs
apt install ./python-wrapt_1.10.11-1+b1_amd64.deb ./python-debtcollector_1.20.0-2_all.deb ./python-roman_2.0.0-3_all.deb ./python-docutils_0.14+dfsg-4_all.deb ./python-babel_2.6.0+dfsg.1-1+deb10u1_all.deb ./python-oslo.i18n_3.21.0-2_all.deb ./python-rfc3986_0.3.1-2_all.deb ./python-stevedore_1.29.0-2_all.deb ./python-yaml_5.1.2-1+b1_amd64.deb ./python-oslo.config_6.4.1-1_all.deb ./python-novnc_1.0.0-1_all.deb ./websockify-common_0.8.0+dfsg1-10_all.deb ./python3-numpy_1.16.2-1+b1_amd64.deb ./python3-websockify_0.8.0+dfsg1-10_amd64.deb ./novnc_1.0.0-1_all.deb
```

Предварительно подключить base и  extended репозитории и выполнить
```
sudo apt update && sudo apt install novnc
```

## Создание карты токенов (матрицы ВМ)
```
sudo mkdir -p /etc/novnc
cat << EOF > /etc/novnc/tokens
# Компьютер 1 (например, IP 192.168.1.11)
pc1-vm1: 192.168.1.11:5901
pc1-vm2: 192.168.1.11:5902
pc1-vm3: 192.168.1.11:5903
pc1-vm4: 192.168.1.11:5904
pc1-vm5: 192.168.1.11:5905


# Компьютер 5 (например, IP 192.168.1.15)
pc1-vm1: 192.168.1.15:5901
pc1-vm2: 192.168.1.15:5902
pc1-vm3: 192.168.1.15:5903
pc1-vm4: 192.168.1.15:5904
pc1-vm5: 192.168.1.15:5905
EOF
```

## Создание службы автозапуска (systemd)
```
cat << EOF > /etc/systemd/system/novnc-instructor.service
[Unit]
Description=noVNC Central Token Server for Classroom
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/websockify --web /usr/share/novnc 8080 --target-config=/etc/novnc/tokens
Restart=always
User=root

[Unit]
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now novnc-instructor
```

## Настройка АРМ обучаемых
> TODO Изменить XML-конфиги ВМ ВМ

Откройте virt-manager, зайдите в свойства каждой ВМ (вкладка «Дисплей VNC»):
ВМ №1: Адрес: 0.0.0.0, Порт: 5901
...
ВМ №5: Адрес: 0.0.0.0, Порт: 5905

## Подключение в браузере
Подключение в браузере по url `http://localhost:8085/vnc.html?path=websockify?token=pc1-vm1&autoconnect=true`
- autoconnect=true — автоматически проскакивает экран приветствия и кнопку.
- resize=scale — автоматически подгоняет разрешение экрана ВМ под размер окна браузера.
- view_only=true — (опционально) блокирует отправку нажатий клавиш и мыши с ПК инструктора, оставляя только режим демонстрации экрана ученика (если инструктору нужно управлять машиной, этот параметр добавлять не нужно)
