# Инструкция по использованию плейбуков

## Требования к управляющей машине (АРМ инструктора)

На компьютере, с которого будет запускаться деплой, должны быть установлены следующие пакеты:
- `ansible` — движок оркестрации;
- `sshpass` — автоматического ввода паролей при первом SSH-подключении (требуется для первого прохода плейбука `init_class.yml`, чтобы автоматически и подставлять пароль администратора в SSH-сессию при запросе `ask_pass = True`;
- `rsync` — утилита синхронизации каталога с образами на машине обучаемого с каталогом `files/images`;
- `genisoimage` — утилита для динамической сборки ISO-образа с файломи из каталога `files/distros`.

## Структура каталогов проекта
Перед самым первым запуском скрипта `vlab.sh` структура рабочего каталога на управляющем ПК должна выглядеть следующим образом:
```text
/opt/vlab/ansible
├── ansible.cfg               # Конфигурация вывода и параметров подключения Ansible
├── hosts                     # Файл инвентаря с IP-адресами машин класса
├── init_class.yml            # Плейбук настройки общей инфраструктуры класса
├── init_user.yml             # Плейбук создания и настройки места ученика
├── clean_user.yml            # Плейбук точечного сброса лабораторной среды
├── vlab.sh                   # Единый Bash-скрипт управления (CLI обертка)
├── files/
│   ├── distros/              # Каталог с файлами, которые будут автоматически собраны в distros.iso
│   ├── images/               # Базовые *.qcow2 образы-шаблоны
│   └── icons/                # Иконки для ярлыков запуска (формат: имя_машины.png)
└── templates/
    ├── intnet.xml            # Шаблон изолированной внутренней сети
    ├── extnet.xml            # Шаблон внешней сети с NAT
    ├── nftables.conf         # Шаблон правил сетевого экрана
    ├── shortcut.desktop.tmpl # Шаблон графического ярлыка запуска ВМ
    ├── arm-abi.xml           # Конфигурация виртуальной машины АРМ-АБИ
    ├── arm-ips.xml           # Конфигурация виртуальной машины АРМ управления СКЗИ
    ├── ips-master.xml        # Конфигурация виртуальной машины КШ с ЦУС
    ├── ips-slave.xml         # Конфигурация виртуальной машины КШ
    ├── rubicon.xml           # Конфигурация виртуальной машины ПК "Рубикон"
    └── srv-szi.xml           # Конфигурация виртуальной машины сервера СЗИ
```

## Отадка по частям
В конец нужных задач ставим тег, например, `tags: testing`, и запускаем плейбук
```
ansible-playbook init_class.yml -l lws-01 --tags "testing"
```
## Развертывание базовой инфраструктуры (выполняется один раз перед курсом на весь класс)
```
ansible-playbook init_class.yml
```
В консоли появится запрос `BECOME password:`, на который необходимо  ввести пароль учетной записи `administrator` на целевых машинах, нажать Enter, и плейбук централизованно настраивает весь класс.

## Создание и настройка рабочего места для конкретного обучаемого на его рабочем месте (например, ivanov на машине lws-01):
```
ansible-playbook init_user.yml -e "host=lws-01 user=ivanov"
```
В консоли появится запрос `BECOME password:`, на который необходимо  ввести пароль учетной записи `administrator` на машине `lws-01` и точечно создаст изолированное окружение для пользователя `ivanov`.

## Полная очистка и сброс рабочего места перед следующим потоком обучаемых
```
ansible-playbook clean_user.yml -e "host=lws-01 user=petrov"
```

## Создание образов дисков
qemu-img create -f qcow2 arm-abi.qcow2 16G
qemu-img create -f qcow2 srv-szi.qcow2 32G

# Инструкция по развертыванию АРМ-О

## Установка ОС
Установку ОС выполняют с настройками по умолчанию, при выборе компонентов отмечают:
- Консольные утилиты
- Средство удаленного управления ssh

## Настройка статического адреса интерфейса eth0
```bash
cat << EOF >> /etc/network/interfaces
auto eth0
iface eth0 inet static
    address 10.0.0.3
    netmask 255.255.255.0
    gateway 10.0.0.1
EOF
```

## Отключение неиспользуемых служб
```bash
sistemctl disable avahi-daemon cups parsec-kiosk2 ufw wpa_supplicant
```

## Устранение ошибки запуска службы astra-event-diagnostics-healthcheck.service
Для устранения ошибки "No module named pkg_resources" при запуске службы `astra-event-diagnostics-healthcheck.service` установить пакет `python3-pkg-resources`
```bash
apt install python3-pkg-resources
```

## Установка docker
```bash
apt install docker.io docker-compose
usermod -aG docker administrator
```

## Отключение проверки уязвимостей OpenSCAP в Docker
```bash
mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "astra-sec-level": 6
}
EOF
systemctl restart docker
```

## Установка образа heywoodlh/vulnerable

Используется предварительно скачанный и загруженный в архив образ `heywoodlh/vulnerable`
```bash
mount /dev/sr0 /media/cdrom
docker load -i /media/cdrom/vulhub_metasploitable3.tar

mkdir -p /opt/vulhub/metasploitable3
cat << EOF > /opt/vulhub/metasploitable3/docker-compose.yml
version: '3.3'

services:
  vulnerable:
    image: heywoodlh/vulnerable
    container_name: metasploitable3
    stdin_open: true # Оставить поток ввода открытым
    tty: true        # Выделить псевдотерминал
    ports:
      - "21:21"      # FTP
      - "2222:22"    # SSH
      - "80:80"      # HTTP
      - "445:445"    # SMB
      - "631:631"    # CUPS
      - "3000:3000"  # Web App / Node
      - "3500:3500"  # App Port
      - "6697:6697"  # IRC SSL
      - "3306:3306"  # MySQL
      - "8181:8181"  # Web Management / Proxy
EOF
```

## Тестовый запуск контейнера
```bash
sudo docker-compose -f /opt/vulhub/metasploitable3/docker-compose.yml up -d
docker ps
# В выводе должна быть строка со сведениями о запущенном контейнере
ef371694d2f3   heywoodlh/vulnerable   "/usr/bin/supervisord"   16 minutes ago   Up 26 seconds   0.0.0.0:21->21/tcp, :::21->21/tcp, 0.0.0.0:80->80/tcp, :::80->80/tcp, 0.0.0.0:445->445/tcp, :::445->445/tcp, 0.0.0.0:631->631/tcp, :::631->631/tcp, 0.0.0.0:3000->3000/tcp, :::3000->3000/tcp, 0.0.0.0:3306->3306/tcp, :::3306->3306/tcp, 0.0.0.0:3500->3500/tcp, :::3500->3500/tcp, 0.0.0.0:6697->6697/tcp, :::6697->6697/tcp, 0.0.0.0:8181->8181/tcp, :::8181->8181/tcp, 0.0.0.0:2222->22/tcp, :::2222->22/tcp   metasploitable3
```


## Создание юнита для автозапуска контейнера metasploitable3
```bash
cat << EOF > /etc/systemd/system/metasploitable3.service
[Unit]
Description=Metasploitable3 Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/vulhub/metasploitable3

# Запуск контейнера из готового локального образа (--no-build)
ExecStart=/usr/bin/docker-compose up -d --no-build

# Остановка (stop) с сохранением состояния контейнера при выключении или перезагрузке
ExecStop=/usr/bin/docker-compose stop

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now metasploitable3.service
```

# Инструкция по развертыванию АРМ управления СКЗИ

> TODO Рассмотреть возможность использования Windows в контейнере
См. [https://github.com/dockur/windows].
    [https://habr.com/ru/companies/ruvds/articles/901004/]

