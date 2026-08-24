BUILD_DIR = /tmp/deb-build
TARGET_DIR = /opt/vlab/ansible


.PHONY: all deb

all: deb

deb:
	@echo "Чтение шаблона deb-пакета..."
	$(eval PKG_NAME := $(shell awk '/^Package:/ {print $$2}' control))
	$(eval BASE_VER  := $(shell awk '/^Version:/ {print $$2}' control))
	$(eval PKG_ARCH := $(shell awk '/^Architecture:/ {print $$2}' control))

	$(eval GIT_REV  := $(shell git rev-list --count HEAD 2>/dev/null || echo 0))
	$(eval PKG_VER  := $(BASE_VER).$(GIT_REV))

	$(eval TMP_BUILD_DIR := $(shell mktemp -d /tmp/deb-build.XXXXXX))

	@echo "Подготовка структуры deb-пакета..."
	@mkdir -p $(TMP_BUILD_DIR)/DEBIAN
	@cp control $(TMP_BUILD_DIR)/DEBIAN/control

	@#cp postinst $(TMP_BUILD_DIR)/DEBIAN/postinst
	@#cp prerm $(TMP_BUILD_DIR)/DEBIAN/prerm
	@#chmod 755 $(TMP_BUILD_DIR)/DEBIAN/postinst
	@#chmod 755 $(TMP_BUILD_DIR)/DEBIAN/prerm

	@echo "Копирование каталогов и файлов проекта..."
	@mkdir -p $(TMP_BUILD_DIR)$(TARGET_DIR)
	@rsync -av --exclude='Makefile' --exclude='control' --exclude='/*.deb' --exclude='.*' --chown=root:root ./ $(TMP_BUILD_DIR)$(TARGET_DIR)

	@echo "Сборка deb-пакета..."
	@sudo dpkg-deb --build $(TMP_BUILD_DIR) $(PKG_NAME)_$(PKG_VER)_$(PKG_ARCH).deb
	@rm -rf $(TMP_BUILD_DIR)
	@echo "Пакет успешно собран: $(PKG_NAME)_$(PKG_VER)_$(PKG_ARCH).deb"
