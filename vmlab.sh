#!/usr/bin/bash

usage() {
  cat << EOF
Использование: $(basename "$0") [-u USER_NAME] -c|-d

Скрипт для автоматической настройки инфраструктуры KVM для УТК-СЗИ.

Параметры:
  -h, --help              Показать эту справку и выйти
  -u, --user ПОЛЬЗОВАТЕЛЬ Имя пользователя
  -c, --create            Создать пул и виртуальные машины пользователя
  -d, --delete            Удалить пул и виртуальные машины пользователя

Примеры запуска:
  $(basename "$0") --create
  $(basename "$0") --user john --delete
EOF
  exit 1
}

# Сделать каталог в котором находится скрипт текущим
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "$EUID" -ne 0 ]; then
  # Перезапустить скрипт $0 со всеми переданными ему аргумитами $@ через sudo
  exec sudo "$0" "$@"
fi

# Использовать системный сеанс, т.к. в сессионном сеансе запуск ВМ в Astra Linux не работает
URI="qemu:///system"

USER=""
# Если хотим применять для текущего пользователя, то раскомментировать
# USER=$(logname)

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -u|--user)
      # Взять следующее значение в качестве имени пользователя и сдвинуть очередь
      shift
      USER="$1"
      ;;
    -с|--create)
      action="create"
      ;;
    -d|--delete)
      action="delete"
      ;;
    *)
      echo "Ошибка: Неизвестный параметр: $1" >&2
      echo "Используйте -h или --help для справки." >&2
      exit 1
      ;;
  esac
  shift
done

SYS_QEMU_DIR="/etc/libvirt/qemu"
SYS_POOL_NAME="default"
SYS_POOL_PATH="/var/lib/libvirt/images"

# Определить путь к домашнему каталогу пользователя
HOME=$(getent passwd "$USER" | cut -d: -f6)
# Определить путь к каталогу рабочего стола
DESKTOP=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
# Имя пула всегда соответствует имени пользователя
export pool_name="$USER"
export pool_path="$HOME/.local/share/libvirt/images"

# Запрошенное действие (создание или удаление виртуальных машин)
if [ -z "$action" ]; then
  echo "Ошибка: Не задано действие"
  exit 2
fi

if [ $action == "delete" ]; then
  # Опция --delete используется только для заданного пользователя
  getent passwd "$USER" &>/dev/null
  if [ $? -ne 0 ]; then
    echo "Error: User missing or not found"
    exit 1
  fi

  read -p "$USER virtual machines will be deleted. Proceed? [y/N]: " response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    # Перебирать все существующие ВМ и удалить те, которые используют пул pool_name
    for vm in $(sudo -u $USER virsh -c "$URI" list --all --name | grep .); do
      # Проверить xml-конфиг на наличие параметра pool='$pool_name'
      sudo -u $USER virsh -c "$URI" dumpxml "$vm" | grep -oP "pool=\'$pool_name\'" &>/dev/null
      if [ $? -eq 0 ]; then
        # Принудительно остановить виртуальную машину, использующую пул
        sudo -u $USER virsh -c "$URI" destroy "$vm" >/dev/null 2>&1
        # Удалить виртуальную машину, использующую пул
        echo -n "Info: "
        sudo -u $USER virsh -c "$URI" undefine "$vm" | grep .
      fi
    done

    # Проверить наличие пула pool_name и удалить, если есть
    virsh -c "$URI" pool-info "$pool_name" &>/dev/null
    if [ $? -eq 0 ]; then
      # Остановить (размонтировать) пул
      echo -n "Info: "
      sudo virsh -c "$URI" pool-destroy $pool_name | grep .
      # Удалить конфигурацию пула из libvirt
      echo -n "Info: "
      sudo virsh -c "$URI" pool-undefine $pool_name | grep .
      # Удалить каталог пула вместе с содержимым
      echo "Info: Каталог пула $pool_name удален"
      rm -rf $pool_path
    fi
    exit 0
  else
    echo "Info: Operation canceled"
    exit 0
  fi
fi

# Создать виртуальные сети, если не созданы
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

# Проверить есть ли изменения в каталоге distros по сравнению с содержимым images/distros.iso
is_changes=$(find distros -type f -newer images/distros.iso -print -quit)
if [ -n "$is_changes" ]; then
  # Создать iso-образ с содержимым каталога distros в подкаталоге images
  genisoimage -input-charset utf-8 -r -J -joliet-long -U -o images/distros.iso distros &>/dev/null && touch images/distros.iso
  echo "Info: distros.iso updated"
fi

# Скопировать базовые образы в системный пул, используя rsync (если установлен) или cp
if [ -f "/usr/bin/rsync" ]; then
  rsync -ahu --progress images/* "$SYS_POOL_PATH"
else
  cp -u images/* "$SYS_POOL_PATH"
fi

# Скопировать иконки к каталог темы оформления
cp -u icons/*.png /usr/share/icons/hicolor/48x48/apps

# Если пользователь не задан или не существует, завершить работу
getent passwd "$USER" &>/dev/null
if [ $? -ne 0 ]; then
  echo "Warning: User missing or not found, skipping user settings on exit"
  exit 0
fi

# Создать каталог пользовательского пула и изменить группу владельца
sudo -u $USER mkdir -p "$pool_path"
chown "$USER":libvirt "$pool_path"
# Установить SGID-бит (2), чтобы новые файлы внутри пула автоматически получали группу libvirt
chmod 2755 "$pool_path"

# Создать оверлейные образы в каталоге пользовательского пула
for filename in $SYS_POOL_PATH/*.qcow2; do
  echo -n "Info: "
  sudo -u $USER qemu-img create -f qcow2 -F qcow2 -b $filename $pool_path/$(basename $filename)
done

# Проверить наличие пула pool_name и зарегистрировать, если он отсутствовал
virsh -c "$URI" pool-info "$pool_name" &>/dev/null
if [ $? -ne 0 ]; then
  # Зарегистрировать стандартный путь как пул KVM, | grep . для подавления вывода пустых строк
  # NB! Запуск с правами пользователя обязателен, иначе завершается с ошибкой!
  sudo -u $USER virsh -c "$URI" pool-define-as "$pool_name" --type dir --target "$pool_path" | grep .
  sudo -u $USER virsh -c "$URI" pool-start "$pool_name" | grep .
  sudo -u $USER virsh -c "$URI" pool-autostart "$pool_name" | grep .
fi
# Зарегистрировать скопированные образы
echo -n "Info: "
sudo -u "$USER" virsh -c "$URI" pool-refresh "$pool_name" | grep .

for filename in *.xml; do
  # При отутствии в каталоге xml выйти из единственной итерации цикла
  [ -e "$filename" ] || continue

  # В качестве имени машины использовать имя xml-файла (без расширения) с суффиксом имени пользователя,
  # экспорт для обработки с помощью envsubst
  export domain_name="${filename%.xml}-$USER"
  # Если машина $domain_name уже существует, пропустить итерацию цикла
  if sudo -u "$USER" virsh -c "$URI" dominfo "$domain_name" >/dev/null 2>&1; then
    echo "Warning: Domain $domain_name allready registered"
    continue
  fi

  # Заменить в шаблоне xml-файла domain_name и pool_name, скопировать файл в каталог системной сессии
  envsubst < "$filename" > "$SYS_QEMU_DIR"/"$filename"
  # Зарегистрировать виртуальную машину в KVM
  echo -n "Info: "
  sudo -u "$USER" virsh -c "$URI" define "$SYS_QEMU_DIR"/"$filename" | grep .
  [[ -f "$pool_path/${filename%.xml}.qcow2" ]] || echo "Warning: Image $pool_path/${filename%.xml}.qcow2 don't exist"

  # Получить заголовок виртуальной машины из тега <title>
  export domain_title=$(grep -Po '^\s*<title>\K.*?(?=</title>)' $filename | head -n 1)
  # Если тега <title> в файле нет, использовать имя домена
  [[ -z "$domain_title" ]] && export domain_title="$domain_name"
  # Используется tee, чтобы создаваемый файл приналежал $USER (через перенаправление не работает)
  envsubst < shortcut.desktop.tmpl | sudo -u "$USER" tee "$DESKTOP/$domain_title.desktop" > /dev/null
  echo "Info: Shortcut for $domain_name created"
done

# Обычно работает без перезапуска, но иногда зависает
# systemctl restart libvirtd
