# Веб-панель инструктора УТК-СЗИ для доступа к интерфейсам виртуальных машин обучаемых с помощью novnc

## Установка novnc на АРМ инструктора
```
# Переход в каталог со скачанными из base- и extended-репозиториями зависимостями novnc и установка novnc
cd ansible-vlab/roles/panel/files
apt install ./python-wrapt_1.10.11-1+b1_amd64.deb ./python-debtcollector_1.20.0-2_all.deb ./python-roman_2.0.0-3_all.deb ./python-docutils_0.14+dfsg-4_all.deb ./python-babel_2.6.0+dfsg.1-1+deb10u1_all.deb ./python-oslo.i18n_3.21.0-2_all.deb ./python-rfc3986_0.3.1-2_all.deb ./python-stevedore_1.29.0-2_all.deb ./python-yaml_5.1.2-1+b1_amd64.deb ./python-oslo.config_6.4.1-1_all.deb ./python-novnc_1.0.0-1_all.deb ./websockify-common_0.8.0+dfsg1-10_all.deb ./python3-numpy_1.16.2-1+b1_amd64.deb ./python3-websockify_0.8.0+dfsg1-10_amd64.deb ./novnc_1.0.0-1_all.deb

# Копирование сервера в целевой каталог
cp index.html server.py /srv/vlab-panel

# Копирование файла токенов в каталог с настройками
mkdir -p /etc/novnc
cp tokens.json /etv/novnc

# Установка и запуска сервера
cp vlab-panel.service /etc/systemd/system
systemctl daemon-reload
systemctl enable --now vlab-panel
```

## Подключение в браузере
Подключение в браузере по url [http://localhost:8080]

