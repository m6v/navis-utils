CONF_DIR = /etc
SYSTEMD_DIR = /etc/systemd/system
NSPAWN_DIR = /etc/systemd/nspawn
BIN_DIR = /usr/local/bin
PROJECT_DIR = /var/lib/machines/ntp-container

.PHONY: all install clean restart status

all: install restart

install:
	@echo "Копирование конфигураций и скриптов..."
	@mkdir -p $(PROJECT_DIR)/upper/etc/chrony
	@mkdir -p $(PROJECT_DIR)/work
	@mkdir -p $(PROJECT_DIR)/merged
	@mkdir -p $(NSPAWN_DIR)
	@cp -f timemachine.conf $(CONF_DIR)/timemachine.conf
	@cp -f ntp-container.nspawn $(NSPAWN_DIR)/ntp-container.nspawn
	@cp -f timemachine.service $(SYSTEMD_DIR)/timemachine.service
	@cp -f timemachine.sh $(BIN_DIR)/timemachine.sh
	@chmod +x $(BIN_DIR)/timemachine.sh
	@cp -f entrypoint.sh $(PROJECT_DIR)/upper/entrypoint.sh
	@chmod +x $(PROJECT_DIR)/upper/entrypoint.sh
	@cp -f chrony.conf $(PROJECT_DIR)/upper/etc/chrony/chrony.conf
	@systemctl daemon-reload

restart:
	@echo "Перезапуск контейнера Машины Времени..."
	@systemctl stop timemachine || true
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@systemctl reset-failed timemachine || true
	@systemctl restart timemachine
	@echo "Служба успешно запущена."

status:
	@-systemctl status timemachine --no-pager

clean:
	@echo "Удаление проекта Машины Времени..."
	@systemctl stop timemachine || true
	@umount -l $(PROJECT_DIR)/merged 2>/dev/null || true
	@rm -f $(CONF_DIR)/timemachine.conf
	@rm -f $(NSPAWN_DIR)/ntp-container.nspawn
	@rm -f $(SYSTEMD_DIR)/timemachine.service
	@rm -f $(SYSTEMD_DIR)/timemachine.socket || true
	@rm -f $(BIN_DIR)/timemachine.sh
	@rm -rf $(PROJECT_DIR)
	@systemctl daemon-reload
	@echo "Очистка завершена."
