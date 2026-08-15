#!/bin/bash

# Остановка скрипта при любой ошибке
set -e

# Переменные пакета
PACKAGE_NAME="ansible-vlab"
VERSION="1.1.2"
MAINTAINER="Sergey Mаksimov <m6v@main.ru>"
DESCRIPTION="Ansible orchestration for virtual laboratory (vlab)"
SOURCE_DIR="./ansible"
DEST_DIR="/srv/vlab"

# Создание временного каталога в /tmp
BUILD_DIR=$(mktemp -d -t deb-build.XXXXXX)

echo "Начало сборки DEB-пакета..."
echo "Временная директория сборки: $BUILD_DIR"

# Проверка наличия исходного каталога с проектом Ansible
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Ошибка: Исходный каталог $SOURCE_DIR не найден!"
    rm -rf "$BUILD_DIR"
    exit 1
fi

# Ловушка (Trap) для очистки врененного каталога после завершения скрипта
trap 'rm -rf "$BUILD_DIR"' EXIT

# Создание структуры каталогов во временном каталоге
mkdir -p "$BUILD_DIR/DEBIAN" "$BUILD_DIR/srv"

# Копирование с сохранением исходных прав (флаг -a сохраняет timestamps, права и ссылки)
echo "Копирование файлов проекта..."
rsync -av --exclude="roles/vlab/files/images" --exclude="roles/vlab/files/distros" "$SOURCE_DIR" "$BUILD_DIR/srv/"

# Создание манифеста пакета (control)
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

# Создание скрипта postinst
echo "Создание скрипта postinst..."
cat << 'EOF' > "$BUILD_DIR/DEBIAN/postinst"
#!/bin/sh
set -e

echo "Настройка прав доступа для $DEST_DIR..."
# Смена владельца на root:sudo
chown -R root:sudo $DEST_DIR

# Установка прав для группы (чтение и запись),
# а бит выполнения добавляем ТОЛЬКО директориям и тем файлам, где он уже был (благодаря заглавной X)
chmod -R g+rwX,o-rwx $DEST_DIR

# Включение SGID на каталоги, чтобы новые файлы наследовали группу sudo
find $DEST_DIR -type d -exec chmod g+s {} +

# Создание симлинка в /usr/local/bin/vlab
if [ ! -L /usr/local/bin/vlab ]; then
    ln -s $DEST_DIR/vlab.sh /usr/local/bin/vlab
    echo "Создан симлинк /usr/local/bin/vlab"
fi

exit 0
EOF

# Установка бита исполнения на сам скрипт postinst
chmod 755 "$BUILD_DIR/DEBIAN/postinst"

# Сборка финального пакета с универсальным флагом сжатия -Zgzip
OUTPUT_DEB="${PACKAGE_NAME}_${VERSION}_all.deb"
echo "Сборка пакета с помощью dpkg-deb..."
dpkg-deb -Zgzip --build "$BUILD_DIR" "$OUTPUT_DEB"

echo "Сборка успешно завершена"
echo "Пакет готов: $(pwd)/$OUTPUT_DEB"
