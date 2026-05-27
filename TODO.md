1. Для использования ВМ rubicon, arm-ips, ips-master, ips-slave создать пользователям оверлейные образы, а базовые образы хранить в системном пуле
qemu-img create -f qcow2 -F qcow2 -b /path/to/base.qcow2 /path/to/overlay.qcow2
2. Для создаваемых виртуальных машин атоматически создавать суффикс из имени пользователя, например, arm-abi-ivanov
4. Попробовать решить задачу манипулирования временем не изнутри виртуальной машины сервера СЗИ, а снаружи (наиболее перспективный способ - использовать qemu-guest-agent)
5. Продумать необходимость автоматического запуска ips-master и ips-slave при запуске arm-ips (использовать хук qemu)

Если будет использоваться qemu-guest-agent, то добавить с конфиг ВМ канал:
```
<channel type="unix">
    <target type="virtio" name="org.qemu.guest_agent.0"/>
    <address type="virtio-serial" controller="0" bus="0" port="1"/>
</channel>
```
на ВМ установить и включить службу `qemu-guest-agent`.
После этих действий можно выполнять команды, например,
```
virsh -c qemu:///system qemu-agent-command "$DOMAIN_NAME" '{"execute":"guest-get-time"}'
```
но команды от root не запускаются, нужно разбираться как заставить

NB! При запуске ВМ с дисками в домашнем каталоге в убунте нужно в файл `/etc/libvirt/qemu.conf` добавить параметр `security_driver = "none"`, как обстоит ситуация в Астре уточнить!
