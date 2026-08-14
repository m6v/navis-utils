CONF_DIR = /etc
SYSTEMD_DIR = /etc/systemd/system
NSPAWN_DIR = /etc/systemd/nspawn
BIN_DIR = /usr/local/bin
PROJECT_DIR = /var/lib/machines/timemachine
TIMESHIFT_FILE = /etc/timeshift
INITIAL_DATE = 2026-01-15 00:00:00



.PHONY: all install clean restart status

all: install restart

install:
	@echo "Копирование конфигураций и скриптов..."
	@mkdir -p $(PROJECT_DIR)/upper/etc/chrony
	@mkdir -p $(PROJECT_DIR)/work
	@mkdir -p $(PROJECT_DIR)/merged
	@mkdir -p $(NSPAWN_DIR)
	@cp -f faketime $(CONF_DIR)/faketime
	@cp -f timemachine.nspawn $(NSPAWN_DIR)/timemachine.nspawn
	@cp -f timemachine.service $(SYSTEMD_DIR)/timemachine.service
	@cp -f timemachine.py $(BIN_DIR)/timemachine.py
	@chmod +x $(BIN_DIR)/timemachine.py
	@cp -f entrypoint.sh $(PROJECT_DIR)/upper/entrypoint.sh
	@chmod +x $(PROJECT_DIR)/upper/entrypoint.sh
	@cp -f chrony.conf $(PROJECT_DIR)/upper/etc/chrony/chrony.conf
	@echo $$(( $$(date -d "$(INITIAL_DATE)" +%s) - $$(date +%s))) > $(TIMESHIFT_FILE)
	@systemctl daemon-reload

restart:
	@echo "Перезапуск контейнера..."
	@systemctl stop timemachine || true
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@systemctl reset-failed timemachine || true
	@systemctl restart timemachine
	@echo "Служба успешно запущена."

status:
	@-systemctl status timemachine --no-pager

clean:
	@echo "Удаление проекта..."
	@systemctl stop timemachine || true
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@rm -f $(CONF_DIR)/faketime
	@rm -f $(NSPAWN_DIR)/timemachine.nspawn
	@rm -f $(SYSTEMD_DIR)/timemachine.service
	@rm -f $(BIN_DIR)/timemachine.py
	@rm -f $(TIMESHIFT_FILE)
	@rm -rf $(PROJECT_DIR)
	@systemctl daemon-reload
	@echo "Очистка завершена."
