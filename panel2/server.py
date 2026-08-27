#!/usr/bin/env python3
import http.server
import json
import os
import subprocess
import sys
import time
import socket

PORT = 8000
WEBSOCKIFY_PORT = 8085

# Определяем папки относительно расположения самого скрипта server.py
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WEBSOCKIFY_BIN = os.path.join(BASE_DIR, 'websockify')
NOVNC_WEB_ROOT = os.path.join(BASE_DIR, 'noVNC-1.6.0')
# Файл tokens.json лежит в одной папке со скриптом
JSON_TOKENS_FILE = os.path.join(BASE_DIR, 'tokens.json') 
FLAT_TOKENS_FILE = '/tmp/tokens.txt'

def check_port(ip, port):
    """Проверка, открыт ли TCP-порт VNC на удаленной ЭВМ"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            result = sock.connect_ex((ip, int(port)))
            return result == 0
    except Exception:
        return False

def rebuild_flat_tokens():
    """Парсинг json-файла конфигурации, проверка статуса ВМ и генерация файла с токенами"""
    tokens_tree = {}
    flat_lines = []

    if not os.path.exists(JSON_TOKENS_FILE):
        print(f"Ошибка: Файл конфигурации {JSON_TOKENS_FILE} не найден!", file=sys.stderr)
        return tokens_tree

    try:
        with open(JSON_TOKENS_FILE, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        for vm_name, vm_info in config_data.items():
            ip_address = vm_info.get("ip", "").strip()
            tokens_dict = vm_info.get("tokens", {})

            if not ip_address:
                continue

            tokens_tree[vm_name] = {
                "ip": ip_address,
                "vms": []
            }

            for key, port in tokens_dict.items():
                token_name = f"{vm_name}-{key.strip()}"
                is_online = check_port(ip_address, port)

                tokens_tree[vm_name]["vms"].append({
                    "token": token_name,
                    "status": "online" if is_online else "offline"
                })

                flat_lines.append(f"{token_name}: {ip_address}:{port}\n")

        with open(FLAT_TOKENS_FILE, 'w', encoding='utf-8') as f:
            f.writelines(flat_lines)

    except json.JSONDecodeError as je:
        print(f"Ошибка синтаксиса в файле конфигурации: {je}", file=sys.stderr)
    except Exception as e:
        print(f"Ошибка при обработке файла конфигурации: {e}", file=sys.stderr)

    return tokens_tree

class NoVNCHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Говорим Python отдавать статику строго из папки noVNC-1.6.0
        super().__init__(*args, directory=NOVNC_WEB_ROOT, **kwargs)

    def do_GET(self):
        # Перехватываем только запрос к API, всё остальное обработает SimpleHTTPRequestHandler
        if self.path == '/api/tokens':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()

            tokens_data = rebuild_flat_tokens()
            self.wfile.write(json.dumps(tokens_data).encode('utf-8'))
            return

        super().do_GET()

def start_websockify():
    """Запуск Go-websockify в режиме чтения файла токенов"""
    # -l задает порт прослушивания
    # -f указывает Go-бинарнику путь к сгенерированному файлу токенов
    cmd = [
        WEBSOCKIFY_BIN,
        '-l', f'0.0.0.0:{WEBSOCKIFY_PORT}',
        '-f', FLAT_TOKENS_FILE
    ]

    print(f"Запуск автономного websockify на порту {WEBSOCKIFY_PORT}...")
    try:
        process = subprocess.Popen(
            cmd, 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
        return process
    except FileNotFoundError:
        print(f"Ошибка: Бинарный файл {WEBSOCKIFY_BIN} не найден!", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    # Проверяем наличие папки со статикой перед стартом
    if not os.path.exists(NOVNC_WEB_ROOT):
        print(f"Ошибка: Папка со статикой {NOVNC_WEB_ROOT} не найдена!", file=sys.stderr)
        sys.exit(1)

    rebuild_flat_tokens()
    websock_proc = start_websockify()
    time.sleep(1)

    print(f"Панель инструктора запущена на http://localhost:{PORT}")

    try:
        server = http.server.HTTPServer(('0.0.0.0', PORT), NoVNCHandler)
        server.serve_forever()
    except BaseException:
        print("\nОстановка серверов...")
    finally:
        if 'websock_proc' in locals() and websock_proc:
            websock_proc.terminate()
            websock_proc.wait()
        if os.path.exists(FLAT_TOKENS_FILE):
            os.remove(FLAT_TOKENS_FILE)
        print("Процессы успешно завершены.")
