1. Добавлять пользователя в libvirt-admin (иначе не создается пул), или создавать пул от рута!
2. Попробовать решить задачу манипулирования временем не изнутри виртуальной машины сервера СЗИ, а снаружи (наиболее перспективный способ - использовать qemu-guest-agent)
2. Продумать необходимость автоматического запуска ips-master и ips-slave при запуске arm-ips (использовать хук qemu)
3. Разобраться для чего в Астре кроме astra-kvm нужен пакет astra-kvm-secure, который по дефолту не ставится и работает без него! Нужно ли вообще добавить функции по установке недостающих пакетов (astra-kvm, qemu-guest-agent, rsync)

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
