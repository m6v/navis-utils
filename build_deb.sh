#!/bin/bash

# Задать остановку скрипта при любой ошибке
set -e

# Переменные пакета
PACKAGE_NAME="ansible-vlab"
VERSION="1.0.0"
MAINTAINER="Your Name <admin@company.com>"
DESCRIPTION="Ansible orchestration for virtual laboratory (vlab)"
SOURCE_DIR="./srv/ansible-vlab"

# Сгенерировать уникальный временный каталог внутри /tmp
BUILD_DIR=$(mktemp -d -t deb-build.XXXXXX)

echo "Начало сборки DEB-пакета..."
echo "Временная директория сборки: $BUILD_DIR"

# Проверить, существует ли исходный каталог с проектом Ansible
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Ошибка: Исходный каталог $SOURCE_DIR не найден!"
    rm -rf "$BUILD_DIR"
    exit 1
fi

# Ловушка (Trap) очистит /tmp в любом случае (при успехе, ошибке или Ctrl+C)
trap 'rm -rf "$BUILD_DIR"' EXIT

# Создать структуру каталогов внутри временной папки
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/srv/ansible-vlab"

# Копировать файлы проекта во временную структуру
echo "Копирование файлов проекта..."
cp -r "$SOURCE_DIR"/. "$BUILD_DIR/srv/ansible-vlab/"

# Создать манифест пакета (control)
echo "Создание файла DEBIAN/control..."
cat << EOF > "$BUILD_DIR/DEBIAN/control"
Package: $PACKAGE_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Maintainer: $MAINTAINER
Depends: ansible, whiptail, sshpass, rsync, genisoimage
Description: $DESCRIPTION
EOF

# Создать скрипт postinst для настройки прав на целевой машине
echo "Создание скрипта postinst..."
cat << 'EOF' > "$BUILD_DIR/DEBIAN/postinst"
#!/bin/sh
set -e

echo "Настройка прав доступа для /srv/ansible-vlab..."
chown -R root:sudo /srv/ansible-vlab
chmod -R 770 /srv/ansible-vlab
find /srv/ansible-vlab -type d -exec chmod g+s {} +

# Делаем сам скрипт меню исполняемым на всякий случай
chmod +x /srv/ansible-vlab/vlab.sh

# Создаем глобальную команду "vlab" для удобства админов
if [ ! -L /usr/local/bin/vlab ]; then
    ln -s /srv/ansible-vlab/vlab.sh /usr/local/bin/vlab
    echo "Создана глобальная команда: vlab"
fi

exit 0
EOF

# Сделать скрипт postinst исполняемым внутри пакета
chmod 755 "$BUILD_DIR/DEBIAN/postinst"

# Собирать финальный пакет в текущую директорию
OUTPUT_DEB="${PACKAGE_NAME}_${VERSION}_all.deb"
echo "Сборка пакета с помощью dpkg-deb..."
dpkg-deb --build "$BUILD_DIR" "$OUTPUT_DEB"

echo "Сборка успешно завершена"
echo "Пакет готов: $(pwd)/$OUTPUT_DEB"
