UNIT_NAME = vlab-servers
STORAGE_ROOT = /opt/vlab/storage
SYSTEMD_DIR = /etc/systemd/system
NSPAWN_DIR = /etc/systemd/nspawn
FAKETIME_FILE = /etc/faketime
INITIAL_DATE = 2026-02-23 03:00:00


.PHONY: all install clean restart stop enter status

all: install restart

install:
	@echo "Копирование конфигураций и скриптов..."
	@mkdir -p $(STORAGE_ROOT)/upper
	@mkdir -p $(STORAGE_ROOT)/work
	@mkdir -p $(STORAGE_ROOT)/merged
	@mkdir -p $(NSPAWN_DIR)
	@cp -f $(UNIT_NAME).nspawn $(NSPAWN_DIR)/$(UNIT_NAME).nspawn
	@cp -f $(UNIT_NAME).service $(SYSTEMD_DIR)/$(UNIT_NAME).service
	@cp -f entrypoint.sh $(STORAGE_ROOT)/upper/entrypoint.sh
	@chmod +x $(STORAGE_ROOT)/upper/entrypoint.sh
	@mkdir -p $(STORAGE_ROOT)/upper/etc/chrony
	@cp -f chrony.conf $(STORAGE_ROOT)/upper/etc/chrony/chrony.conf
	@echo $$(date -d "$(INITIAL_DATE)" +%s) > $(FAKETIME_FILE)
	@systemctl daemon-reload

enter:
	@nsenter --target $$(machinectl show $(UNIT_NAME) -p Leader --value) --mount --net --uts --ipc --pid /bin/bash

restart:
	@echo "Перезапуск контейнера..."
	@systemctl stop $(UNIT_NAME) || true
	@systemctl reset-failed $(UNIT_NAME) 2>/dev/null || true
	@systemctl restart $(UNIT_NAME)
	@echo "Служба успешно запущена."

stop:
	@echo "Останов контейнера..."
	@systemctl stop $(UNIT_NAME) || true
	@echo "Служба успешно остановлена."

status:
	@-systemctl status $(UNIT_NAME) --no-pager

clean:
	@echo "Удаление проекта..."
	@systemctl stop $(UNIT_NAME) || true
	@umount -l $(STORAGE_ROOT)/merged 2>/dev/null || true
	@rm -f $(NSPAWN_DIR)/$(UNIT_NAME).nspawn
	@rm -f $(SYSTEMD_DIR)/$(UNIT_NAME).service
	@rm -f $(TIMESHIFT_FILE)
	@rm -rf $(STORAGE_ROOT)
	@systemctl daemon-reload
	@echo "Очистка завершена."
