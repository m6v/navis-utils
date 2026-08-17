UNIT_NAME = vlab-servers
SYSTEMD_DIR = /etc/systemd/system
NSPAWN_DIR = /etc/systemd/nspawn
PROJECT_DIR = /opt/vlab/servers
FAKETIME_FILE = /etc/faketime
INITIAL_DATE = 2026-02-23 03:00:00


.PHONY: all install clean restart stop enter status

all: install restart

install:
	@echo "Копирование конфигураций и скриптов..."
	@mkdir -p $(PROJECT_DIR)/upper
	@mkdir -p $(PROJECT_DIR)/work
	@mkdir -p $(PROJECT_DIR)/merged
	@mkdir -p $(NSPAWN_DIR)
	@cp -f $(UNIT_NAME).nspawn $(NSPAWN_DIR)/$(UNIT_NAME).nspawn
	@cp -f $(UNIT_NAME).service $(SYSTEMD_DIR)/$(UNIT_NAME).service
	@cp -f entrypoint.sh $(PROJECT_DIR)/upper/entrypoint.sh
	@chmod +x $(PROJECT_DIR)/upper/entrypoint.sh
	@mkdir -p $(PROJECT_DIR)/upper/etc/chrony
	@cp -f chrony.conf $(PROJECT_DIR)/upper/etc/chrony/chrony.conf
	@echo $$(date -d "$(INITIAL_DATE)" +%s) > $(FAKETIME_FILE)
	@systemctl daemon-reload

enter:
	nsenter --target $$(machinectl show $(UNIT_NAME) -p Leader --value) --mount --net --uts --ipc --pid /bin/bash

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
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@rm -f $(NSPAWN_DIR)/$(UNIT_NAME).nspawn
	@rm -f $(SYSTEMD_DIR)/$(UNIT_NAME).service
	@rm -f $(TIMESHIFT_FILE)
	@rm -rf $(PROJECT_DIR)
	@systemctl daemon-reload
	@echo "Очистка завершена."
