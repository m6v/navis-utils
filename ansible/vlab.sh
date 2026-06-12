#!/usr/bin/env bash

set -euo pipefail

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

# Функция запроса имени пользователя
prompt_user_name() {
    user=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Ввод" --cancel-button "Назад" --inputbox "Введите имя пользователя:" 10 55 "" 3>&1 1>&2 2>&3) || return 1
    [ -z "$user" ] && return 1 || return 0
}

# Функция подготовки аргументов и запуска ansible-playbook
run_ansible() {
    local playbook=$1
    local user=$2
    local parms=""

    clear
    
    # Формирование готовой строки параметров запуска
    if [ -n "$user" ]; then
        parms="-e 'host=$host user=$user'"
    else
        [ "$host" != "ALL" ] && parms="-e 'host=$host'"
    fi

    # Одинарные кавычки защищают синтаксис команды,
    # двойные раскрывают переменные без экранирования слэшами
    eval 'ansible-playbook "'"$playbook"'" '"$parms" || true
    
    read -n 1 -s -r -p "Нажмите любую клавишу..."
}

# Главный цикл панели управления
while true; do
    # Инициализация и принудительный сброс параметров перед каждым действием
    host=""
    user=""

    choice=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Выбрать" --cancel-button "Выход" --menu "Выберите действие:" 15 65 5 \
        "1" "Инициализировать среду виртуализации" \
        "2" "Создать учетную запись пользователя" \
        "3" "Создать пул виртуальных машин пользователя" \
        "4" "Удалить пул виртуальных машин пользователя" \
        "5" "Удалить учетную запись и пул виртуальных машин" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$choice" ]; then
        clear
        exit 0
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
        whiptail --title "Подтверждение" --backtitle "$HINT" --ok-button "Да" --cancel-button "Нет" --yesno "Удалить пользователя '$user' и пул на хосте '$host'?" 10 60 || continue
    fi

    run_ansible "$playbook" "$user"
done
