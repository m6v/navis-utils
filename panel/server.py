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
CONFIG_JSON_FILE = '/etc/novnc/tokens.json'   # Путь к новому JSON файлу
FLAT_TOKENS_FILE = '/tmp/novnc_flat_tokens'    # Временный файл для websockify
NOVNC_WEB_ROOT = '/usr/share/novnc'

def check_port(ip, port):
    """Быстро проверяет, открыт ли TCP-порт VNC на удаленной ЭВМ"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            result = sock.connect_ex((ip, int(port)))
            return result == 0
    except Exception:
        return False

def rebuild_flat_tokens():
    """Парсит JSON файл, проверяет статус ВМ и генерирует плоский файл для websockify"""
    tokens_tree = {}
    flat_lines = []

    if not os.path.exists(CONFIG_JSON_FILE):
        print(f"Ошибка: Файл конфигурации {CONFIG_JSON_FILE} не найден!", file=sys.stderr)
        return tokens_tree

    try:
        # Нативное чтение структуры из JSON
        with open(CONFIG_JSON_FILE, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        for pc_name, pc_info in config_data.items():
            ip_address = pc_info.get("ip", "").strip()
            tokens_dict = pc_info.get("tokens", {})
            
            if not ip_address:
                continue
            
            # Сохраняем обратную совместимость структуры для ответа API (/api/tokens)
            tokens_tree[pc_name] = {
                "ip": ip_address,
                "vms": []
            }

            for key, port in tokens_dict.items():
                token_name = f"{pc_name}-{key.strip()}"
                
                # Проверяем реальный статус ВМ прямо сейчас
                is_online = check_port(ip_address, port)
                
                tokens_tree[pc_name]["vms"].append({
                    "token": token_name,
                    "status": "online" if is_online else "offline"
                })
                
                # Формируем строку в строгом формате websockify
                flat_lines.append(f"{token_name}: {ip_address}:{port}\n")

        # Записываем плоский файл для websockify
        with open(FLAT_TOKENS_FILE, 'w', encoding='utf-8') as f:
            f.writelines(flat_lines)

    except json.JSONDecodeError as je:
        print(f"Ошибка синтаксиса в JSON-файле: {je}", file=sys.stderr)
    except Exception as e:
        print(f"Ошибка при обработке конфигурации: {e}", file=sys.stderr)

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
        print("Внимание: Скрипт запущен без прав root. Доступ к /etc/novnc/tokens.json может быть заблокирован.", file=sys.stderr)
    
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
        if 'websock_proc' in locals():
            websock_proc.terminate()
            websock_proc.wait()
        if os.path.exists(FLAT_TOKENS_FILE):
            os.remove(FLAT_TOKENS_FILE)
        print("Процессы успешно завершены.")
