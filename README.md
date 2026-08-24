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

# Инструкция по ручному развертыванию и использованию vlab

1. Создаем каталог под правами root:
```
sudo mkdir -p /srv/ansible-vlab
```
2. Копируем туда файлы проекта
3. Настраиваем права доступа через общую группу:
Обычно на таких серверах все администраторы уже входят в группу sudo или wheel. Давайте отдадим права этой группе
```
# Меняем владельца на root, а группу — на sudo
sudo chown -R root:sudo /srv/ansible-vlab

# Даем права: root и группа sudo могут читать/писать/выполнять, остальные — ничего
sudo chmod -R 770 /srv/ansible-vlab
```
4. Включаем SGID-бит
Если один администратор создаст внутри проекта новый файл (например, новый плейбук или лог), по умолчанию владельцем файла станет его личная группа, и другие админы не смогут его отредактировать. Чтобы этого не произошло, выполните
```
sudo chmod g+s /srv/ansible-vlab
sudo find /srv/ansible-vlab -type d -exec chmod g+s {} +
```
Теперь любые новые файлы внутри этой папки будут автоматически наследоваться группой sudo, и вся команда сможет работать без багов с правами.

Если будет использоваться qemu-guest-agent, то добавить с конфиг ВМ канал:
```
<channel type="unix">
    <target type="virtio" name="org.qemu.guest_agent.0"/>
    <address type="virtio-serial" controller="0" bus="0" port="1"/>
</channel>
```
На ВМ установить пакет `qemu-guest-agent` и включить службу `qemu-guest-agent`.

После этих действий можно выполнять команды, например, qemu-agent-command
```
virsh -c qemu:///system qemu-agent-command "$DOMAIN_NAME" '{"execute":"guest-get-time"}'
```

NB! При запуске ВМ с дисками в домашнем каталоге в убунте нужно в файл `/etc/libvirt/qemu.conf` добавить параметр `security_driver = "none"`, как обстоит ситуация в Астре уточнить!

Чтобы при запуске графического интерфейса virt-manager сразу отображалось и автоматически открывалось подключение к пользовательской сессии, нужно настроить параметры virt-manager.
В Debian 13 настройка выполнена с помощью следующих команд
```
# Установить команду gsettings
sudo apt install libglib2.0-bin

# Задать список подключений
gsettings set org.virt-manager.virt-manager.connections uris "['qemu:///session']"

# Включить для qemu:///session автоматическое подключение при старте
gsettings set org.virt-manager.virt-manager.connections autoconnect "['qemu:///session']"

```

Чтобы постоянно не указывать сессию настроить переменную LIBVIRT_DEFAULT_URI
```
export LIBVIRT_DEFAULT_URI="qemu:///session"
```

## Настройка пула
```
# Создать каталог пула
mkdir -p ~/.local/share/libvirt/images"
# Определить и создать пул "default", указывающий на стандартную домашнюю папку ВМ
virsh -с qemu:///session pool-define-as default dir --target ~/.local/share/libvirt/images
# Активировать пул
virsh -с qemu:///session pool-start default
# Включить автозапуск пула при каждом старте сессии
virsh -с qemu:///session pool-autostart default
# Настроить конфиг для запуска ВМ в сессии пользователя
echo 'security_driver = "none"' >> ~/.config/libvirt/qemu.conf
```

## Создание сети
```
# Зарегистрировать сеть intnet в системной сессии libvirt
echo "<network><name>intnet</name><bridge name='virbr0' stp='on' delay='0'/></network>" | sudo virsh net-define /dev/stdin
# Включить автоматический запуск сети при загрузке ПК
sudo virsh net-autostart intnet
# Запустить сеть прямо сейчас
sudo virsh net-start intnet
```

## Настройка разрешения на подключение машин в пользовательской сессии, к мостам virbr0 и virbr1
```
sudo mkdir -p /etc/qemu
echo "allow virbr0" | sudo tee -a /etc/qemu/bridge.conf
echo "allow virbr1" | sudo tee -a /etc/qemu/bridge.conf
sudo chmod 4755 /usr/lib/qemu/qemu-bridge-helper
```

## Создать виртуальные машины
```
# Если нужно настраивать шаблон, то
domain_name=test envsubst < arm-abi.xml | virsh -c qemu:///session define /dev/stdin
# Если настройка не нужна, то
cat arm-abi.xml | virsh -c qemu:///session define /dev/stdin
# или
virsh -c qemu:///session define <(cat arm-abi.xml)
```

## Удалить виртуальные машины
```
# Принудительно остановить все запущенные машины в сессии
virsh -c qemu:///session list --name | xargs -I {} virsh -c qemu:///session destroy "{}"

# Удалить регистрацию (конфигурацию) всех машин
virsh -c qemu:///session list --all --name | xargs -I {} virsh -c qemu:///session undefine "{}" --nvram
```
