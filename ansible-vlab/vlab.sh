#!/usr/bin/env bash

set -euo pipefail

# Определить реальный каталог скрипта 
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# Перейти реальный каталог скрипта перед выполнением остального кода
cd "$SCRIPT_DIR" || exit 1

TITLE="Панель управления рабочими станциями УТК-СЗИ"
INVENTORY_FILE="hosts"
HINT="Управление: [Стрелки] - движение, [Tab] - кнопки, [Enter] - выбор"

# Проверка наличия файла инвентаря
if [ ! -f "$INVENTORY_FILE" ]; then
    whiptail --title "Ошибка" --msgbox "Файл инвентаря '$INVENTORY_FILE' не найден!" 8 55
    exit 1
fi

# Список плейбуков с индексами, соответствующими пунктам меню
# Нулевой индекс пропускается, так как меню начинается с 1
PLAYBOOKS=(
    ""
    "site.yml"
    "create_user.yml"
    "define_user_pool.yml"
    "destroy_user_pool.yml"
    "delete_user.yml"
)

# Функция выбора хоста из инвентаря
select_host_from_inventory() {
    local menu_options=()
    
    # Пункт "ALL" доступен только для плейбуков, не привязанных к конкретному пользователю
    [ "$is_user_required" = false ] && menu_options+=("ALL" "Все хосты")

    while read -r name ip; do
        [ ! -z "$name" ] && [ ! -z "$ip" ] && menu_options+=("$name" "$ip")
    done < <(awk -F'[ =]' '$2 == "ansible_host" { print $1, $3 }' "$INVENTORY_FILE")

    host=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Выбрать" --cancel-button "Назад" --menu "Выберите целевой хост:" 18 65 10 "${menu_options[@]}" 3>&1 1>&2 2>&3) || return 1
    [ -z "$host" ] && return 1 || return 0
}

# Функция подготовки аргументов и запуска ansible-playbook
run_ansible() {
    local playbook="$1"
    local user="$2"
    
    clear

    # Массив аргументов
    local ansible_args=()

    # Добавление переменных host и user
    if [ -n "$user" ]; then
        ansible_args+=("-e" "host=$host user=$user")
    elif [ "$host" != "ALL" ]; then
        ansible_args+=("-e" "host=$host")
    fi

    # Добавление параметров авторизации ssh и sudo
    ansible_args+=("-e" "ansible_user=$ansible_user ansible_password=$ansible_password ansible_sudo_pass=$ansible_password")

    # Запуск ansible-playbook с передачей элементов массива ansible_args как отдельных независимых аргументов
    ansible-playbook "$playbook" "${ansible_args[@]}" || true
    
    read -n 1 -s -r -p "Нажмите любую клавишу..."
}

# Функция запроса имени пользователя
prompt_user_name() {
    # Если указан первый аргумент, использовать его как дефолтный логин 
    user_name="${1:-}"
    while true; do
        if user_name=$(whiptail --title "$TITLE" \
            --backtitle "$HINT" \
            --ok-button "Ввод" \
            --cancel-button "Отмена" \
            --inputbox "\nВведите логин пользователя:" 10 55 "$user_name" \
            3>&1 1>&2 2>&3); then
            # Обработка нажатия "Ввод"
            [ -n "$user_name" ] && return 0
            # Уход на новую итерацию, если ввод пустой
            user_name=""
        else
            # Обработка нажатия "Отмена" или "Esc"
            return 1
        fi
    done
}

prompt_user_pass() {
    user_pass=$(whiptail --title "$TITLE" \
        --backtitle "$HINT" \
        --ok-button "Далее" \
        --cancel-button "Отмена" \
         --passwordbox "\nВведите пароль пользователя:" 10 55 \
        3>&1 1>&2 2>&3) || return 1
    # [ -z "$user_pass" ] && return 1 || return 0
    return 0
}

prompt_user_name "administrator"
prompt_user_pass

ansible_user=$user_name
ansible_password=$user_pass

# Главный цикл панели управления
while true; do
    # Инициализация и принудительный сброс параметров перед каждым действием
    host=""
    user_name=""

    choice=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Выбрать" --cancel-button "Выход" --menu "\nВыберите действие:" 15 65 6 \
        "1" "Инициализировать среду виртуализации" \
        "2" "Создать учетную запись пользователя" \
        "3" "Создать пул и виртуальные машины пользователя" \
        "4" "Удалить пул и виртуальные машины пользователя" \
        "5" "Удалить учетную запись пользователя" \
        "6" "Показать справку" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$choice" ]; then
        clear
        exit 0
    fi

    if [ "$choice" -eq 6 ]; then
        # Проверить наличие файла справки в текущем каталоге
        if [ -f "help.txt" ]; then
            whiptail --title "Справка" \
                     --backtitle "$HINT" \
                     --scrolltext \
                     --textbox "help.txt" 20 75
        else
            whiptail --title "Ошибка" \
                     --backtitle "$HINT" \
                     --msgbox "Файл help.txt не найден в текущем каталоге!" 8 50
        fi
        continue
    fi
    
    # Чтение имени плейбука по индексу выбранного пункта меню
    playbook="${PLAYBOOKS[$choice]}"
    
    # Определение необходимости выбора имени пользователя по имени плейбука
    # (в плейбуках, содержащих user в названии, требуется задать пользователя)
    if [[ "$playbook" == *"user"* ]]; then
        is_user_required=true
    else
        is_user_required=false
    fi

    # Конвейер шагов интерфейса
    select_host_from_inventory || continue
    [ "$is_user_required" = true ] && { prompt_user_name || continue; }

    # Индивидуальное исключение для подтверждения удаления (пункт 3)
    if [ "$choice" -eq 5 ]; then
        whiptail --title "Подтверждение" --backtitle "$HINT" --ok-button "Да" --cancel-button "Нет" --yesno "Удалить пользователя '$user_name' на '$host'?" 10 60 || continue
    fi

    run_ansible "$playbook" "$user_name"
done
