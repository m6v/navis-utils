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
  -p, --pool POOL_NAME Имя пула хранения (по умолчанию совпадает с именем пользователя)
  -u, --user USER_NAME Имя пользователя (по умолчанию текущий пользователь)

Примеры запуска:
  $(basename "$0") --user john
  $(basename "$0") --user john --pool my_pool
EOF
  exit 1
}

# Содать на рабочем столе ярлык запуска виртуальной машины,
# имя xml-файла которой передается в первом аргументе
create_shortcuts () {
  local domain_name
  domain_name=$(basename "$1" .xml)

  # Имя ярлыка виртуальной машины взять из тега <title>
  local domain_title
  domain_title=$(grep -Po '^\s*<title>\K.*?(?=</title>)' "$1" | head -n 1)

  # Если тега <title> в файле нет, использовать имя домена
  [[ -z "$domain_title" ]] && domain_title="$domain_name"

  # Определить путь к каталогк рабочего стола
  local desktop
  desktop=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")

  local shortcut="$desktop/$domain_title.desktop"

  cat <<EOF > "$shortcut"
[Desktop Entry]
Version=1.0
Type=Application
Name=$domain_title
Comment=Запуск виртуальной машины $domain_title
Exec=sh -c "virsh --connect qemu:///system start '$domain_name'; virt-manager --connect qemu:///system --show-domain-console '$domain_name'"
Icon=virt-manager
Terminal=false
Categories=System;Emulator;
EOF

  chmod +x "$shortcut"
  echo "$domain_name icon created"
}

if [ "$EUID" -ne 0 ]; then
  # Перезапустить скрипт ($0) со всеми переданными ему аргумитами ($@) через sudo
  exec sudo "$0" "$@"
fi

# Кроме astra-kvm есть пакет astra-kvm-secure, но работает и без него
# apt install -y astra-kvm

# Использовать системный сеанс, т.к. в сессионном сеансе запуск ВМ в Astra Linux не работает
URI="qemu:///system"

# NB! При запуске из файлового менеджера может не работать!
USER=$(logname)

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -с|--connect)
      # Взять в качестве URI подключения к гипервизору
      # следующее значение и сдвинуть очередь
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
    -u|--user)
      # Взять следующее значение в качестве имени пользователя и сдвинуть очередь
      shift
      USER="$1"
      ;;
    *)
      echo "Ошибка: Неизвестный параметр: $1" >&2
      echo "Используйте -h или --help для справки." >&2
      exit 1
      ;;
  esac
  shift
done

if ! getent passwd "$USER" &>/dev/null; then
  echo "Error: User '$USER' not exist"
  exit 1
fi

HOME=$(getent passwd "$USER" | cut -d: -f6)

POOL_NAME="$USER"
POOL_PATH="$HOME/.local/share/libvirt/images"

SYS_QEMU_DIR="/etc/libvirt/qemu"

# Создать виртуальные сети
for network_name in intnet extnet; do
  virsh -c "$URI" net-info $network_name &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Сеть $network_name не установлена, выполняем установку"
    # Установить и запустить сеть $network_name
    virsh -c "$URI" net-define <(echo "<network><name>${network_name}</name></network>")
    virsh net-start $network_name
    virsh net-autostart $network_name
  fi
done

# Создать каталог пула и изменить группу
sudo -u $USER mkdir -p "$POOL_PATH"
chown "$USER":libvirt "$POOL_PATH"
# Установить SGID-бит (2), чтобы новые файлы внутри пула автоматически получали группу kvm
chmod 2755 "$POOL_PATH"

# Скопировать все образы в созданный пул:
# скобки для запуска в изолированной оболочке (subshell),
# umask 007 задает создаваемым файлам права 660,
# параметр -u замена только более старых файлов
(umask 007 && sudo -u "$USER" find . -type f -name "*.qcow2" -exec cp -u --no-preserve=mode {} "$POOL_PATH" \;)

# Проверить наличие пула $POOL_NAME и создать, если он отсутствовал
virsh -c "$URI" pool-info "$POOL_NAME"
if [ $? -ne 0 ]; then
  # Зарегистрировать стандартный путь как пул KVM
  # NB! Запуск с правами пользователя обязателен, иначе завершается с ошибкой!
  sudo -u $USER virsh -c "$URI" pool-define-as "$POOL_NAME" --type dir --target "$POOL_PATH"
  sudo -u $USER virsh -c "$URI" pool-start "$POOL_NAME"
  sudo -u $USER virsh -c "$URI" pool-autostart "$POOL_NAME"
fi
# Зарегистрировать скопированные образы
sudo -u "$USER" virsh -c qemu:///system pool-refresh "$POOL_NAME"

for filename in *.xml; do
  # При отутсвтии в каталоге xml выйти из цикла
  [ -e "$filename" ] || continue
  # В качестве имени машины использовать имя xml-файла (без расширения)
  domain_name="${filename%.xml}"
  # Если машина $domain_name уже существует, пропустить итерацию цикла
  if sudo -u "$USER" virsh -c qemu:///system dominfo "$domain_name" >/dev/null 2>&1; then
    echo "Domain $domain_name allready registered"
    echo
    continue
  fi
  cp $filename $SYS_QEMU_DIR
  # Заменить шаблоны имени машины и пула в xml-файле актуальными значениями
  sed -i -e "s|{domain_name}|$domain_name|g" -e "s|{pool_name}|$POOL_NAME|g" "$SYS_QEMU_DIR"/"$filename"
  # Зарегистрировать виртуальную машину в KVM
  sudo -u "$USER" virsh -c qemu:///system define "$SYS_QEMU_DIR"/"$filename"
  create_shortcuts $filename
done

# Создать iso-образ с содержимым каталога distros
genisoimage -input-charset utf-8 -r -J -joliet-long -U -o distros.iso distros

SYS_POOL_NAME="default"
SYS_POOL_PATH="/var/lib/libvirt/images"
# Скопировать все iso в системный пул
find . -type f -name "*.iso" -exec cp -u {} "$SYS_POOL_PATH" \;

systemctl restart libvirtd
