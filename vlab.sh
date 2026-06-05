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
  -f, --force             Перезаписывать существующие образы дисков виртуальных машин пользователя

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

# Добавить root'а в группу libvirt-admin, чтобы выполнять служебные операции
if ! id -nG root | grep -q "\blibvirt-admin\b"; then
    usermod -aG "libvirt-admin" root
    systemctl restart libvirtd
fi

# Если пользователь не задан, использовать текущего
USER=$(logname)

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
    -f|--force)
      force="y"
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

URI="qemu:///system"

# Определить путь к домашнему каталогу пользователя
HOME=$(getent passwd "$USER" | cut -d: -f6)
# Определить путь к каталогу рабочего стола
DESKTOP=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
# Определить имя и каталог пользовательского пула
export USER_POOL_NAME="$USER"
export USER_POOL_PATH="$HOME/.local/share/libvirt/images"

# Функция-обертка для virsh
vrun() {
    sudo -E -u $USER XDG_RUNTIME_DIR="/run/user/$(id -u $USER)" virsh -c $URI $@
}

# Запрошенное действие (создание или удаление виртуальных машин)
if [ -z "$action" ]; then
  echo "Ошибка: Не задано действие"
  exit 2
fi

if [ $action == "delete" ]; then
  # Опция --delete всегда должна использоваться с опцией -u, --user
  getent passwd "$USER" &>/dev/null
  if [ $? -ne 0 ]; then
    echo "Error: User missing or not found"
    exit 1
  fi

  read -p "User '$USER' domains will be deleted. Proceed? [y/N]: " response
  if ! [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Info: Operation canceled"
    exit 0
  fi

  # Удалить ярлыки виртуальных машин
  for filename in $DESKTOP/*.desktop; do
    grep "X-Related-To=vlab" "$filename" &>/dev/null
    if [ $? -eq 0 ]; then
      rm "$filename"
    fi
  done

  # Проверить, включен linger у пользователя или нет
  is_linger_on=$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)
  # Принудительно включить Linger (постоянное присутствие) для пользователя
  loginctl enable-linger "$USER"

  # Перебирать все существующие ВМ и удалить те, которые используют пул USER_POOL_NAME
  for vm in $(vrun list --all --name | grep .); do
    # Проверить xml-конфиг на наличие параметра pool='$USER_POOL_NAME'
    vrun dumpxml "$vm" | grep -oP "pool=\'$USER_POOL_NAME\'" &>/dev/null
    if [ $? -eq 0 ]; then
      # Принудительно остановить виртуальную машину, использующую пул
      vrun destroy "$vm" >/dev/null 2>&1
      # Удалить виртуальную машину и NVRAM, использующую пул
      echo -n "Info: "
      vrun undefine "$vm" --nvram | grep .
    fi
  done


  # Выключить Linger
  if [ "$is_linger_on" == "no" ]; then
    loginctl disable-linger "$USER" 2>/dev/null
  fi

  # Проверить наличие пула USER_POOL_NAME и удалить, если есть
  vrun pool-info "$USER_POOL_NAME" &>/dev/null
  if [ $? -eq 0 ]; then
    # Остановить (размонтировать) пул
    echo -n "Info: "
    vrun pool-destroy $USER_POOL_NAME | grep .
    # Удалить конфигурацию пула из libvirt
    echo -n "Info: "
    vrun pool-undefine $USER_POOL_NAME | grep .
    # Удалить каталог пула вместе с содержимым
    echo "Info: Каталог пула $USER_POOL_NAME удален"
    rm -rf $USER_POOL_PATH
  fi
  exit 0
fi

# Создать виртуальные сети, если не созданы
for network_name in intnet extnet; do
  vrun net-info $network_name &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Installing $network_name network"
    # Установить и запустить сеть $network_name (первой команде передается имя файла, остальным - имя сети)
    # vrun net-define $network_name
    # vrun net-start $network_name
    # vrun net-autostart $network_name
    virsh -c $URI net-define $network_name
    virsh -c $URI net-start $network_name
    virsh -c $URI net-autostart $network_name
  fi
done

# Проверить есть ли изменения в каталоге distros по сравнению с содержимым images/distros.iso (если файл есть)
is_changes=$(find distros -type f -newer images/distros.iso -print -quit)
# Обновить образ, если он отсутствует или в каталоге distros есть более свежие файлы, чем в images/distros.iso
if ! [ -f images/distros.iso ] || [ -n "$is_changes" ]; then
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

# Если пользователь не задан или не существует, на этом завершить работу
getent passwd "$USER" &>/dev/null
if [ $? -ne 0 ]; then
  echo "Warning: User missing or not found, skipping user settings on exit"
  exit 0
fi

# Создать каталог пользовательского пула и изменить группу владельца
sudo -u $USER mkdir -p "$USER_POOL_PATH"
chown "$USER":libvirt "$USER_POOL_PATH"
# Установить SGID-бит (2), чтобы новые файлы внутри пула автоматически получали группу libvirt
chmod 2755 "$USER_POOL_PATH"

# Создать оверлейные образы в каталоге пользовательского пула
for filename in $SYS_POOL_PATH/*.qcow2; do
  # Создать только отсутствующие образы или пересоздать все, если задан аргумент -f, --force
  if [ ! -f $USER_POOL_NAME/$(basename $filename) ] || [ -n "$force" ]; then
    echo -n "Info: "
    sudo -u $USER qemu-img create -f qcow2 -F qcow2 -b $filename $USER_POOL_PATH/$(basename $filename)
  else
    echo "Warning: File $USER_POOL_PATH/$(basename $filename) exists. Skipping"
  fi
done

# Проверить наличие пула USER_POOL_NAME и зарегистрировать, если он отсутствовал
vrun pool-info $USER_POOL_NAME &>/dev/null
if [ $? -ne 0 ]; then
  # Зарегистрировать стандартный путь как пул KVM, | grep . для подавления вывода пустых строк
  echo pool-define-as "$USER_POOL_NAME" --type dir --target "$USER_POOL_PATH"
  vrun pool-define-as "$USER_POOL_NAME" --type dir --target "$USER_POOL_PATH" | grep .
  vrun pool-start $USER_POOL_NAME | grep .
  vrun pool-autostart $USER_POOL_NAME | grep .
fi

# Зарегистрировать скопированные образы
echo -n "Info: "
vrun pool-refresh $USER_POOL_NAME | grep .

# Использовать полный путь, т.к. относительный при запуске runuser -l "$USER" теряется
for filename in $(pwd)/*.xml; do
  # При отутствии в каталоге xml выйти из единственной итерации цикла
  [ -e "$filename" ] || continue

  # В качестве имени машины использовать имя файла (без расширения .xml)
  domain_name=$(basename "$filename" .xml)
  export domain_name

  # Если машина $domain_name уже существует, пропустить итерацию цикла
  if runuser -l "$USER" -c "virsh dominfo $domain_name >/dev/null 2>&1"; then
    echo "Warning: Domain $domain_name allready registered"
    continue
  fi

  # Зарегистрировать виртуальную машину в KVM
  echo -n "Info: "
  envsubst < "$filename" > /tmp/vm.xml
  vrun define /tmp/vm.xml | grep .
  [[ -f "$USER_POOL_PATH/$domain_name.qcow2" ]] || echo "Warning: Image $USER_POOL_PATH/$domain_name.qcow2 don't exist"

  # Получить заголовок виртуальной машины из тега <title>
  export domain_title=$(grep -Po '^\s*<title>\K.*?(?=</title>)' "$filename" | head -n 1)
  # Если тега <title> в файле нет, использовать имя домена
  [[ -z "$domain_title" ]] && export domain_title="$domain_name"
  # Используется tee, чтобы создаваемый файл приналежал $USER (через перенаправление не работает)
  envsubst < shortcut.desktop.tmpl | sudo -u "$USER" tee "$DESKTOP/$domain_title.desktop" > /dev/null
  echo "Info: Shortcut for $domain_name created"
done

# Перезапустить libvirtd, запущенный в контексте $USER, если использовалать сессия пользователя
if [ "$URI" = "qemu:///session" ]; then
  runuser -l "$USER" -c "killall -HUP libvirtd 2>/dev/null"
fi
