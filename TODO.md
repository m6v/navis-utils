1. В плейбуке создания пользователя сделать выход, если пользователь существует, вместо проверки соответствующей переменной в каждой задаче. И наоборот в задаче удаления пользователя!
2. Переделать передачу имен хостов в виде списка и разрешать выбор нескольких хостов (если получится добавить кнопку "Выбрать все" и "Очистить")
3. Попробовать решить задачу манипулирования временем не изнутри виртуальной машины сервера СЗИ, а снаружи (наиболее перспективный способ - использовать qemu-guest-agent)
4. Продумать необходимость автоматического запуска ips-master и ips-slave при запуске arm-ips (использовать хук qemu)
5. Разобраться для чего в Астре нужен пакет astra-kvm-secure, который по дефолту не ставится и виртуализация работает без него

В качестве места размещения проекта в соответствии со стандартом FHS (Filesystem Hierarchy Standard) могут использоваться каталоги /srv или /usr/local/src/

Согласно стандарту FHS (Filesystem Hierarchy Standard), каталог /srv предназначен для хранения данных конкретных сервисов и хост-систем, к которым нужен общий доступ.
Каталог /usr/local/src/ исторически используется для хранения исходных кодов программ и скриптов, установленных локально администратором, а не из официальных репозиториев ОС.
Как правильно настроить права для совместной работы

Просто скопировать проект в /srv/ansible-vlab/ недостаточно, нужно сделать так, чтобы все администраторы могли с ним работать без конфликтов прав.

Вот готовый рецепт, как развернуть проект в /srv на машине администратора:

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
