#!/usr/bin/bash

usage() {
  cat << EOF
Использование: $(basename "$0") [ПАРАМЕТРЫ]

Скрипт для автоматической настройки инфраструктуры KVM для УТК-СЗИ.

Параметры:
  -h, --help           Показать эту справку и выйти
  -c, --connect URI    URI подключения к гипервизору (Hypervisor Connection URI).
                       Определяет контекст драйвера и режим работы libvirt.
                       Допустимые значения:
                         qemu:///system   - Системный режим (System mode). Демон работает
                                            с правами root, есть полный доступ к сети хоста.
                         qemu:///session  - Пользовательский режим (Session mode). Ограничен
                                            правами текущего пользователя в его сессии.
                      (По умолчанию: qemu:///system)
  -p, --pool POOL_NAME Имя пула хранения (по умолчанию совпадает с именем пользователя).

Примеры запуска:
  $(basename "$0")
  $(basename "$0") --connect qemu:///session --pool my_pool
EOF
  exit 1
}

if [ "$EUID" -ne 0 ]; then
  # Перезапустить скрипт ($0) со всеми переданными ему аргумитами ($@) через sudo
  exec sudo "$0" "$@"
fi

# Кроме astra-kvm есть пакет astra-kvm-secure, но работает и без него
apt install -y astra-kvm

# Использовать системный сеанс, т.к. в сессионном сеансе запуск ВМ в Astra Linux не работает
URI="qemu:///system"

# NB! При запуске из файлового менеджера может не работать!
USER=$(logname)
HOME=$(getent passwd "$USER" | cut -d: -f6)

POOL_NAME="$USER"
POOL_PATH="$HOME/.local/share/libvirt/images"

SYS_QEMU_DIR="/etc/libvirt/qemu"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -с|--connect)
      # Взять следующее значение в качестве URI подключения к гипервизору и сдвинуть очередь
      shift
      if [[ "$1" == "qemu:///system" || "$1" == "qemu:///session" ]]; then
        URI="$1"
      else
        echo "Ошибка: Неверное значение для параметра --connect: '$1'" >&2
        echo "Допустимые значения: 'qemu:///system' или 'qemu:///session'" >&2
        exit 1
      fi
      ;;
    -p|--pool)
      # Взять следующее значение в качестве имени пула и сдвинуть очередь
      shift
      POOL_NAME="$1"
      ;;
    *)
      echo "Ошибка: Неизвестный параметр: $1" >&2
      echo "Используйте -h или --help для справки." >&2
      exit 1
      ;;
  esac
  shift
done

# Создать виртуальные сети
for net_name in intnet extnet; do
  virsh -c "$URI" net-info $net_name &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Сеть $net_name не установлена, выполняем установку"
    # Установить и запустить сеть $net_name
    virsh -c "$URI" net-define <(echo "<network><name>${net_name}</name></network>")
    virsh net-start $net_name
    virsh net-autostart $net_name
  fi
done

# Обеспечить права доступа libvirt к домашней папке
chmod o+x $HOME
# Создать всю цепочку стандартных директорий и выставить права
mkdir -p "$POOL_PATH"
chown -R "$USER":libvirt "$HOME/.local" 2>/dev/null || chown -R "$USER":root "$HOME/.local"
chmod 775 "$POOL_PATH"

# Проверить наличие пула $POOL_NAME и создать, если отсутствовал
virsh -c "$URI" pool-info "$POOL_NAME"
if [ $? -ne 0 ]; then
  # Зарегистрировать стандартный путь как пул KVM
  # NB! Запуск с правами пользователя обязателен, иначе завершается с ошибкой!
  sudo -u $USER virsh -c "$URI" pool-define-as "$POOL_NAME" --type dir --target "$POOL_PATH"
  sudo -u $USER virsh -c "$URI" pool-start "$POOL_NAME"
  sudo -u $USER virsh -c "$URI" pool-autostart "$POOL_NAME"
fi

# Скопировать все образы в созданный пул и зарегистрировать их
# NB! При копировании замещаются только более старые файлы (флаг -u)
sudo -u "$USER" find . -type f -name "*.qcow2" -exec cp -u {} "$POOL_PATH" \;
sudo -u "$USER" virsh -c qemu:///system pool-refresh "$POOL_NAME"

for filename in *.xml; do
  # При отутсвтии в каталоге xml выйти из цикла
  [ -e "$filename" ] || continue
  vm_name="${filename%.xml}"
  # Проверить, существует ли машина $vm_name
  if sudo -u "$USER" virsh -c qemu:///system dominfo "$vm_name" >/dev/null 2>&1; then
    echo "Domain '$vm_name' allready registered"
    echo
    continue
  fi
  cp "$vm_name".xml $SYS_QEMU_DIR
  # Заменить шаблоны имени машины и пула актуальными значениями
  sed -i -e "s|{vm_name}|$vm_name|g" -e "s|{pool_name}|$USER|g" "$SYS_QEMU_DIR"/"$filename"
  # Зарегистрировать виртуальную машину в KVM
  sudo -u "$USER" virsh -c qemu:///system define "$SYS_QEMU_DIR"/"$filename"
done

# Создать iso-образ с содержимым каталога distros
genisoimage -J -joliet-long -U -o distros.iso distros

POOL_NAME="default"
POOL_PATH="/var/lib/libvirt/images"
# Скопировать все iso в системный пул
find . -type f -name "*.iso" -exec cp -u {} "$POOL_PATH" \;
