CONF_DIR = /etc
SYSTEMD_DIR = /etc/systemd/system
NSPAWN_DIR = /etc/systemd/nspawn
BIN_DIR = /usr/local/bin
PROJECT_DIR = /var/lib/vlab-storage
TIMESHIFT_FILE = /etc/timeshift
INITIAL_DATE = 2026-01-01 00:00:00


.PHONY: all install clean restart status

all: install restart

install:
	@echo "Копирование конфигураций и скриптов..."
	@mkdir -p $(PROJECT_DIR)/upper/etc/chrony
	@mkdir -p $(PROJECT_DIR)/work
	@mkdir -p $(PROJECT_DIR)/merged
	@mkdir -p $(NSPAWN_DIR)
	@cp -f vlab-servers.nspawn $(NSPAWN_DIR)/vlab-servers.nspawn
	@cp -f vlab-servers.service $(SYSTEMD_DIR)/vlab-servers.service
	@cp -f timeshifter $(BIN_DIR)/timeshifter
	@chmod +x $(BIN_DIR)/timeshifter
	@cp -f entrypoint.sh $(PROJECT_DIR)/upper/entrypoint.sh
	@chmod +x $(PROJECT_DIR)/upper/entrypoint.sh
	@cp -f chrony.conf $(PROJECT_DIR)/upper/etc/chrony/chrony.conf
	@echo $$(( $$(date -d "$(INITIAL_DATE)" +%s) - $$(date +%s))) > $(TIMESHIFT_FILE)
	@systemctl daemon-reload

restart:
	@echo "Перезапуск контейнера..."
	@systemctl stop vlab-servers || true
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@systemctl reset-failed vlab-servers 2>/dev/null || true
	@systemctl restart vlab-servers
	@echo "Служба успешно запущена."

status:
	@-systemctl status vlab-servers --no-pager

clean:
	@echo "Удаление проекта..."
	@systemctl stop vlab-servers || true
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@rm -f $(CONF_DIR)/faketime
	@rm -f $(NSPAWN_DIR)/vlab-servers.nspawn
	@rm -f $(SYSTEMD_DIR)/vlab-servers.service
	@rm -f $(BIN_DIR)/timeshifter
	@rm -f $(TIMESHIFT_FILE)
	@rm -rf $(PROJECT_DIR)
	@systemctl daemon-reload
	@echo "Очистка завершена."
