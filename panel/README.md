# Веб-панель инструктора УТК-СЗИ для доступа к интерфейсам виртуальных машин обучаемых с помощью novnc

## Установка novnc на АРМ инструктора
```
# Переход в каталог со скачанными из base- и extended-репозиториями зависимостями novnc и установка novnc
cd ansible-vlab/roles/panel/files
# apt умеет работать с локальными файлами, анализирует зависимости между скачанными пакетами и выстроит их в правильный порядок
apt install ./*.deb

# Копирование сервера в целевой каталог
mkdir -p /opt/vlab/panel
cp index.html server.py virt-manager.png /opt/vlab/panel

# Копирование файла токенов в каталог с настройками
mkdir -p /etc/novnc
cp tokens.json /etv/novnc

# Установка и запуска сервера
cp vlab-panel.service /etc/systemd/system
systemctl daemon-reload
systemctl enable --now vlab-panel
```

## Подключение в браузере
Подключение в браузере по url [http://localhost:8080]

Задача установки для ansible
```
- name: Копирование и установка noVNC с зависимостями
  hosts: all
  become: true
  vars:
    # Путь к папке с .deb пакетами на локальном компьютере
    local_src_dir: "/home/user/downloads/novnc_packages/"
    # Временная папка на удаленном компьютере, куда прилетят файлы
    remote_dest_dir: "/tmp/novnc_deb_packages/"

  tasks:
    - name: Создание временной папки на целевом хосте
      ansible.builtin.file:
        path: "{{ remote_dest_dir }}"
        state: directory
        mode: '0755'

    - name: Копирование всех .deb пакетов на целевой хост
      ansible.builtin.copy:
        src: "{{ local_src_dir }}" # Копируем содержимое локальной папки
        dest: "{{ remote_dest_dir }}"
        mode: '0644'

    - name: Поиск скопированных deb-файлов на целевом хосте
      ansible.builtin.find:
        paths: "{{ remote_dest_dir }}"
        patterns: "*.deb"
      register: found_deb_files

    - name: Установка пакетов в правильном порядке
      ansible.builtin.apt:
        deb: "{{ item.path }}"
      loop: "{{ found_deb_files.files }}"

    - name: Очистка временных файлов (удаление папки с deb)
      ansible.builtin.file:
        path: "{{ remote_dest_dir }}"
        state: absent

```
