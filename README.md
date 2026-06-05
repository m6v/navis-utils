# Скрипт автоматизации развертывания и удаления виртуальных машин УТК-СЗИ

Скрипт vmlab.sh выполняет следующие действия:
1. Проверяет наличие и в случае отсутствия создает виртуальные сети `intnet` и `extnet`;
2. Создает images/distros.iso с файлами из подкаталога distros;
3. Копирует все образы из каталога images в системный пул;
4. Создает новый пул с именем пользователя, указанного в параметре --user;
5. Создает в пуле пользователя оверлейные образы из базовых qcow2-образов в системном пуле;
6. Копирует из текущего каталога все qcow2-образы дисков в созданный пул и регистрирует их;
7. Создает виртуальные машины по всем xml-описаниям, имеющимся в текущем каталоге.

## Действия после установки Astra Linux
```
# Удалить ufw
sudo apt purge ufw -y

# Установить службу управления nftables
sudo apt install nftables -y

# Создать эталонный файл правил в файле /etc/nftables.conf
cat << EOF > /etc/nftables.conf
#!/usr/sbin/nft -f

# Полностью очистить старые правила перед загрузкой
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Разрешить уже установленные и доверенные соединения
        ct state established,related accept

        # Разрешить локальную петлю (loopback) для внутренних служб
        iif "lo" accept

        # Разрешить пинг (ICMP)
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # Открыть порты SSH (22) и VNC (5900)
        tcp dport 22 accept
        tcp dport 5900 accept
    }

    chain forward {
        type filter hook forward priority filter; policy accept;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

# Включить nftables и добавить его в автозагрузку операционной системы
sudo systemctl enable --now nftables

# Установить метапакет astra-kvm
sudo apt install astra-kvm

# Отключить устанавливаемый вместе с astra-kvm фаервол firewalld
sudo systemctl stop firewalld
sudo systemctl mask firewalld

# Перевести libvirt на нативный nftables
sudo echo 'firewall_backend = "nftables"' >> /etc/libvirt/network.conf

# Перезапустить виртуализацию для применения настроек
sudo systemctl restart libvirtd
```

## Создание пустых образов
```
qemu-img create -f qcow2 arm-abi.qcow2 16G
qemu-img create -f qcow2 srv-szi.qcow2 32G
```

## Действия в процессе развертывания
```
# Включить пользователя root в группу libvirt-admin
usermod -aG libvirt-admin root
# Включить пользователя в группы для работы со средой виртуализации
sudo usermod -a -G kvm,libvirt,libvirt-qemu,libvirt-admin $USER
```

Если после экспериментов в каталоге /var/lib/libvirt/qemu остаются подкаталоги от несуществующих машин, остановить службу `libvirtd`, удалить подкаталоги и запустить службу.

# Разграничение доступа пользователей к виртуальным машинам в системной сессии
Для разграничения доступа пользователей к виртуальным машинам в системной сессии (qemu:///system), нужно настроить ACL (Access Control Lists) внутри самого libvirt, связав его с правилами Polkit.

## Включение ACL в libvirt
По умолчанию libvirt использует политику «всё или ничего». Чтобы включить точечную проверку прав, в файле `/etc/libvirt/libvirtd.conf` задать параметр `access_drivers = [ "polkit" ]`
и перезапустить службу виртуализации `sudo systemctl restart libvirtd`, а в Astra дополнительно установить пакет `apt install astra-kvm-secure`.

# Успешный запуск в пользовательской сессии
После многочисленных попыток запуска ВМ в пользовательской сессии помогло добавление параметра, отключающего Parsec-драйвер безопасности для пользователя помогло
```
sudo echo 'security_driver = "none"' >> ~/.config/libvirt/qemu.conf
```

NB! Нужно понять повлияли каким-то образом предыдущие настройки или изначально было достаточно установить этот параметр!
Перед запуском были почищены остаточные конфигурации
```
mkdir -p ~/.cache/libvirt/qemu/log
sudo chown -R m6v:m6v ~/.cache/libvirt
```
сброщена привязка к Parsec-драйверам
```
pkill -f libvirtd
```
Содержимое файла ~/.config/libvirt/qemu.conf, возможно какие-то параметры не нужны, установить это после переустановки системы! Но заработало после security_driver = "none"
```
# Полностью отключаем контрольные группы (cgroups) для пользовательских машин
cgroup_controllers = [ ]
# Запрещаем libvirt динамически менять владельцев образов дисков
remember_owner = 0
# Указываем запускать процессы строго от вашего имени (m6v)
user = "m6v"
group = "m6v"
security_driver = "none"
```

Создание нового пользователя и запуск виртуальных машин показал, что достаточно только security_driver = "none" в ~/.config/libvirt/qemu.conf! При создании новой виртуалки в пользователской сессии автоматически создается пул `default` в `$HOME/.local/share/libvirt/images`, что то же существенно облегчает настройку. В этот пул можно сразу копировать оверлейные образы, единственное, что нужно понять как создается этот дефолтный путь, каким-то образом "дернуть" libvirt, чтобы он создал необходимый набор конфигов и структуру каталогов!

Принудительный перезапуск пользовательской службы
```
sudo -E -u $USER XDG_RUNTIME_DIR="/run/user/$(id -u $USER)" systemctl --user restart libvirtd.service 2>/dev/null
```
Часто помогает удаление кэша
```
rm -rf ~/.cache/libvirt/* ~/.config/libvirt/libvirt.conf /run/user/$(id -u)/libvirt*
```

Сетевое взаимодействие через виртуальные мосты не заработало, несмотря на стандартные для этого варианта настройки машин в пользовательской сессии. Для сетевого взаимодействия используется сетевой хаб (Multicast), который поддерживается абсолютно всегда (независимо от версии libvirt), работает строго в сессии обычного пользователя (qemu:///session) и не требует  прав root или системных мостов хоста.
На всех машинах подключенных к одному сегменту сети используется следующий конфиг
```
<interface type='mcast'>
  <source address='230.0.0.1' port='1234'/>
  <model type='virtio'/>
</interface>
```
Для другого сегмента сети нужно задавать другой IP-адрес
