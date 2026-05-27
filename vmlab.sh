#!/usr/bin/bash

usage() {
  cat << EOF
Использование: $(basename "$0") [-u USER_NAME] -c|-d

Скрипт для автоматической настройки инфраструктуры KVM для УТК-СЗИ.

Параметры:
  -h, --help           Показать эту справку и выйти
  -u, --user USER_NAME Имя пользователя (по умолчанию текущий пользователь)
  -c, --create         Создать пул и виртуальные машины пользователя
  -d, --delete         Удалить пул и виртуальные машины пользователя

Примеры запуска:
  $(basename "$0") --create
  $(basename "$0") --user john --delete
EOF
  exit 1
}

# Сделать каталог в котором находится скрипт текущим
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "$EUID" -ne 0 ]; then
  # Перезапустить скрипт ($0) со всеми переданными ему аргумитами ($@) через sudo
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

# Запрошенное действие (создание или удаление виртуальных машин)
if [ -z "$action" ]; then
  echo "Ошибка: Не задано действие"
  exit 2
fi

SYS_QEMU_DIR="/etc/libvirt/qemu"
SYS_POOL_NAME="default"
SYS_POOL_PATH="/var/lib/libvirt/images"

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

# Создать iso-образ с содержимым каталога distros в подкаталоге images
genisoimage -input-charset utf-8 -r -J -joliet-long -U -o images/distros.iso distros &>/dev/null
# Скопировать все iso из подкаталога images в системный пул
find images -type f -name "*.iso" -exec cp -u {} "$SYS_POOL_PATH" \;

# Скопировать базовые образы дисков в системный пул и создать их оверлейные образы в текущем каталоге
for filename in images/*.qcow2; do
  cp -u $filename $SYS_POOL_PATH
  echo -n "Info: "
  qemu-img create -f qcow2 -F qcow2 -b $SYS_POOL_PATH/$(basename $filename) $(basename $filename)
done

# Скопировать иконки к каталог темы оформления
cp icons/*.png /usr/share/icons/hicolor/48x48/apps

if [ -z "$USER" ]; then
  # Если пользователь не задан, завершить работу
  echo "Warning: User not defined, skipping user settings on exit"
  exit 0
fi

if ! getent passwd "$USER" &>/dev/null; then
  echo "Error: No user '$USER' exist"
  exit 1
fi

# Определить путь к домашнему каталогу пользователя USER
HOME=$(getent passwd "$USER" | cut -d: -f6)
# Определить путь к каталогу рабочего стола
DESKTOP=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
# Имя пула всегда соответствует имени пользователя
export pool_name="$USER"
export pool_path="$HOME/.local/share/libvirt/images"

# Создать каталог пула и изменить группу
sudo -u $USER mkdir -p "$pool_path"
chown "$USER":libvirt "$pool_path"
# Установить SGID-бит (2), чтобы новые файлы внутри пула автоматически получали группу kvm
chmod 2755 "$pool_path"

# Скопировать qcow2 образы из текущего каталога в созданный пул пользователя
# скобки для запуска в изолированной оболочке (subshell),
# umask 007 маскирует (сбрасывает) права остальных пользователей копируемых файлов
# параметр -u замена только более старых файлов
(umask 007 && sudo -u "$USER" find . -type f -name "*.qcow2" -exec cp -u --no-preserve=mode {} "$pool_path" \;)

# Проверить наличие пула pool_name и создать, если он отсутствовал
virsh -c "$URI" pool-info "$pool_name"
if [ $? -ne 0 ]; then
  # Зарегистрировать стандартный путь как пул KVM, | grep . для подавления вывода пустых строк
  # NB! Запуск с правами пользователя обязателен, иначе завершается с ошибкой!
  sudo -u $USER virsh -c "$URI" pool-define-as "$pool_name" --type dir --target "$pool_path" | grep .
  sudo -u $USER virsh -c "$URI" pool-start "$pool_name" | grep .
  sudo -u $USER virsh -c "$URI" pool-autostart "$pool_name" | grep .
fi
# Зарегистрировать скопированные образы
echo -n "Info: "
sudo -u "$USER" virsh -c qemu:///system pool-refresh "$pool_name" | grep .

for filename in *.xml; do
  # При отутсвтии в каталоге xml выйти из единственной итерации цикла
  [ -e "$filename" ] || continue

  # В качестве имени машины использовать имя xml-файла (без расширения),
  # экспорт для корректной работы envsubst
  export domain_name="${filename%.xml}"
  # Если машина $domain_name уже существует, пропустить итерацию цикла
  if sudo -u "$USER" virsh -c qemu:///system dominfo "$domain_name" >/dev/null 2>&1; then
    echo "Warning: Domain $domain_name allready registered"
    continue
  fi

  # Скопировать конфиг в каталог системного сеанса
  cp $filename $SYS_QEMU_DIR
  # Заменить шаблон пула в xml-файле значением pool_name и скопировать файл в каталог системной сессии
  envsubst < "$filename" > "$SYS_QEMU_DIR"/"$filename"
  # Зарегистрировать виртуальную машину в KVM
  sudo -u "$USER" virsh -c qemu:///system define "$SYS_QEMU_DIR"/"$filename"
  [[ -f "$domain_name.qcow2" ]] || echo "Warning: Image $domain_name.qcow2 don't exist"

  # Получить заголовок виртуальной машины из тега <title>
  export domain_title=$(grep -Po '^\s*<title>\K.*?(?=</title>)' $filename | head -n 1)
  # Если тега <title> в файле нет, использовать имя домена
  [[ -z "$domain_title" ]] && export domain_title="$domain_name"
  # Используется tee, чтобы создаваемый файл приналежал $USER (через перенаправление не работает)
  envsubst < shortcut.desktop.tmpl | sudo -u "$USER" tee "$DESKTOP/$domain_title.desktop" > /dev/null
  echo "Info: Shortcut for $domain_name created"
done

# systemctl restart libvirtd
