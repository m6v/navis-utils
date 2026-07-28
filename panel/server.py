#!/usr/bin/env python3
import http.server
import json
import os
import subprocess
import sys
import time
import configparser
import socket

PORT = 8000
WEBSOCKIFY_PORT = 8085
CONFIG_INI_FILE = '/etc/novnc/tokens'          # Ваш INI файл
FLAT_TOKENS_FILE = '/tmp/novnc_flat_tokens'    # Временный файл для websockify
NOVNC_WEB_ROOT = '/usr/share/novnc'

def check_port(ip, port):
    """Быстро проверяет, открыт ли TCP-порт VNC на удаленной ЭВМ"""
    try:
        # Ставим минимальный таймаут, чтобы опрос 50 машин не вешал сервер
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            result = sock.connect_ex((ip, int(port)))
            return result == 0  # True если порт открыт (ВМ запущена)
    except Exception:
        return False

def rebuild_flat_tokens():
    """Парсит INI файл с секциями, проверяет статус ВМ и генерирует плоский файл для websockify"""
    tokens_tree = {}
    flat_lines = []

    if not os.path.exists(CONFIG_INI_FILE):
        print(f"Ошибка: Файл конфигурации {CONFIG_INI_FILE} не найден!", file=sys.stderr)
        return tokens_tree

    try:
        config = configparser.ConfigParser()
        config.read(CONFIG_INI_FILE)

        for section in config.sections():
            if 'ip' not in config[section]:
                continue
            
            ip_address = config[section]['ip'].strip()
            tokens_tree[section] = {
                "ip": ip_address,
                "vms": []
            }

            for key, value in config[section].items():
                if key == 'ip':
                    continue
                
                token_name = f"{section}-{key.strip()}"
                port = value.strip()
                
                # Проверяем реальный статус ВМ прямо сейчас
                is_online = check_port(ip_address, port)
                
                # Добавляем в дерево объект с именем токена и его статусом
                tokens_tree[section]["vms"].append({
                    "token": token_name,
                    "status": "online" if is_online else "offline"
                })
                
                flat_lines.append(f"{token_name}: {ip_address}:{port}\n")

        with open(FLAT_TOKENS_FILE, 'w') as f:
            f.writelines(flat_lines)

    except Exception as e:
        print(f"Ошибка при парсинге INI-файла: {e}", file=sys.stderr)

    return tokens_tree

class ProxmoxSimHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/tokens':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            tokens_data = rebuild_flat_tokens()
            self.wfile.write(json.dumps(tokens_data).encode('utf-8'))
        else:
            super().do_GET()

def start_websockify():
    """Запуск websockify в фоновом режиме на базе сгенерированного файла"""
    cmd = [
        '/usr/bin/websockify',
        '--web', NOVNC_WEB_ROOT,
        str(WEBSOCKIFY_PORT),
        '--target-config=' + FLAT_TOKENS_FILE
    ]
    
    print(f"Запуск websockify на порту {WEBSOCKIFY_PORT}...")
    try:
        process = subprocess.Popen(
            cmd, 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
        return process
    except FileNotFoundError:
        print("Ошибка: утилита /usr/bin/websockify не найдена. Установите пакет novnc.", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    if os.getuid() != 0:
        print("Внимание: Скрипт запущен без прав root. Доступ к /etc/novnc/tokens может быть заблокирован.", file=sys.stderr)
    
    rebuild_flat_tokens()
    websock_proc = start_websockify()
    time.sleep(1)
    
    print(f"Интерфейс Комплекса запущен на http://localhost:{PORT}")
    
    try:
        server = http.server.HTTPServer(('0.0.0.0', PORT), ProxmoxSimHandler)
        server.serve_forever()
    except BaseException:
        print("\nОстановка серверов...")
    finally:
        websock_proc.terminate()
        websock_proc.wait()
        if os.path.exists(FLAT_TOKENS_FILE):
            os.remove(FLAT_TOKENS_FILE)
        print("Процессы успешно завершены.")
