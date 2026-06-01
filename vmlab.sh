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
usermod -aG libvirt-admin root

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

# Определить путь к домашнему каталогу пользователя
HOME=$(getent passwd "$USER" | cut -d: -f6)
# Определить путь к каталогу рабочего стола
DESKTOP=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
# Определить имя и каталог пользовательского пула
export pool_name="default"
export pool_path="$HOME/.local/share/libvirt/images"

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

  read -p "$USER virtual machines will be deleted. Proceed? [y/N]: " response
  if ! [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Info: Operation canceled"
    exit 0
  fi

  # Перебирать все существующие ВМ и удалить те, которые используют пул pool_name
  # for vm in $(runuser -l "$USER" -c "virsh -c qemu:///session list --all --name | grep ."); do
  #   # Принудительно остановить виртуальную машину, использующую пул
  #  runuser -l "$USER" -c "virsh -c qemu:///session destroy $vm >/dev/null 2>&1"
  #   # Удалить виртуальную машину, использующую пул
  #  echo -n "Info: "
  #  runuser -l "$USER" -c "virsh -c qemu:///session undefine $vm | grep ."
  #   # TODO Удалить ярлык виртуальной машины с рабочего стала пользователя
  # done

  # Проверить, включен ли уже linger у пользователя или нет
  is_linger_on=$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)
  # Принудительно включить Linger (постоянное присутствие) для пользователя
  loginctl enable-linger "$USER"

  VIRSH_CMD="sudo -u $USER XDG_RUNTIME_DIR=/run/user/$(id -u "$USER") virsh -c qemu:///session"
  echo $($VIRSH_CMD list --all --name)
  echo $(sudo -u $USER virsh -c qemu:///session list --name)

  for vm in $($VIRSH_CMD list --all --name); do
    # Пропустить пустые строки
    [ -z "$vm" ] && continue

    echo "Обработка машины: $vm"

    # Принудительно тушим (если машина работает)
    $VIRSH_CMD destroy "$vm" 2>/dev/null

    # Пауза для закрытия файловых блокировок до удаления XML
    sleep 0.1

    # Удалить конфигурацию и NVRAM из памяти и с диска
    $VIRSH_CMD undefine "$vm" --nvram
  done

  # Выключить Linger
  if [ "$is_linger_on" == "no" ]; then
    loginctl disable-linger "$USER" 2>/dev/null
  fi

  exit 0

  # Проверить наличие пула pool_name и удалить, если есть
  sudo -u $USER virsh pool-info "$pool_name" &>/dev/null
  if [ $? -eq 0 ]; then
    # Остановить (размонтировать) пул
    echo -n "Info: "
    sudo -u $USER virsh pool-destroy $pool_name | grep .
    # Удалить конфигурацию пула из libvirt
    echo -n "Info: "
    sudo -u $USER virsh pool-undefine $pool_name | grep .
    # Удалить каталог пула вместе с содержимым
    echo "Info: Каталог пула $pool_name удален"
    rm -rf $pool_path
  fi
  exit 0
fi

i=0
# Создать виртуальные сети, если не созданы
for network_name in intnet extnet; do
  virsh net-info $network_name &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Installing $network_name network"
    # Установить и запустить сеть $network_name
    echo "<network><name>$network_name</name><bridge name='virbr$i' stp='on' delay='0'/></network>" | sudo virsh net-define /dev/stdin
    virsh net-start $network_name
    virsh net-autostart $network_name
  fi
  ((++i))
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
sudo -u $USER mkdir -p "$pool_path"
chown "$USER":libvirt "$pool_path"
# Установить SGID-бит (2), чтобы новые файлы внутри пула автоматически получали группу libvirt
chmod 2755 "$pool_path"

# Создать оверлейные образы в каталоге пользовательского пула
for filename in $SYS_POOL_PATH/*.qcow2; do
  # Создать только отсутствующие образы или пересоздать все, если задан аргумент -f, --force
  if [ ! -f $pool_path/$(basename $filename) ] || [ -n "$force" ]; then
    echo -n "Info: "
    sudo -u $USER qemu-img create -f qcow2 -F qcow2 -b $filename $pool_path/$(basename $filename)
  else
    echo "Warning: File $pool_path/$(basename $filename) exists. Skipping"
  fi
done

# Проверить наличие пула pool_name и зарегистрировать, если он отсутствовал
runuser -l "$USER" -c "virsh pool-info $pool_name &>/dev/null"
if [ $? -ne 0 ]; then
  # Зарегистрировать стандартный путь как пул KVM, | grep . для подавления вывода пустых строк
  # NB! Запуск с правами пользователя обязателен, иначе завершается с ошибкой
  runuser -l "$USER" -c "virsh -c qemu:///session pool-define-as $pool_name --type dir --target $pool_path | grep ."
  runuser -l "$USER" -c "virsh -c qemu:///session pool-start $pool_name | grep ."
  runuser -l "$USER" -c "virsh -c qemu:///session pool-autostart $pool_name | grep ."
fi
# Зарегистрировать скопированные образы
echo -n "Info: "
runuser -l "$USER" -c "virsh -c qemu:///session pool-refresh $pool_name | grep ."

# Использовать полный путь, т.к. относительный при запуске runuser -l "$USER" теряется
for filename in $(pwd)/*.xml; do
  # При отутствии в каталоге xml выйти из единственной итерации цикла
  [ -e "$filename" ] || continue

  # В качестве имени машины использовать имя файла (без расширения .xml)
  domain_name=(basename "$filename" .xml)

  # Если машина $domain_name уже существует, пропустить итерацию цикла
  if runuser -l "$USER" -c "virsh dominfo $domain_name >/dev/null 2>&1"; then
    echo "Warning: Domain $domain_name allready registered"
    continue
  fi

  # Зарегистрировать виртуальную машину в KVM
  echo -n "Info: "
  # Обязательно указывать $current_dir, т.к. при runuser -l "$USER" все окружение меняется
  runuser -l "$USER" -c "virsh -c qemu:///session define $filename | grep ."
  [[ -f "$pool_path/$domain_name.qcow2" ]] || echo "Warning: Image $pool_path/$domain_name.qcow2 don't exist"

  # Получить заголовок виртуальной машины из тега <title>
  export domain_title=$(grep -Po '^\s*<title>\K.*?(?=</title>)' $filename | head -n 1)
  # Если тега <title> в файле нет, использовать имя домена
  [[ -z "$domain_title" ]] && export domain_title="$domain_name"
  # Используется tee, чтобы создаваемый файл приналежал $USER (через перенаправление не работает)
  envsubst < shortcut.desktop.tmpl | sudo -u "$USER" tee "$DESKTOP/$domain_title.desktop" > /dev/null
  echo "Info: Shortcut for $domain_name created"
done

# Перезапустить libvirtd, запущенный в контексте $USER
runuser -l "$USER" -c "killall -HUP libvirtd 2>/dev/null"
