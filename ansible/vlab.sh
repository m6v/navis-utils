#!/usr/bin/env bash

# Финальный функциональный код обертки Ansible
set -euo pipefail

TITLE="Панель управления виртуальным полигоном"
INVENTORY_FILE="hosts"
HINT="Управление: [Стрелки] - движение, [Tab] - кнопки, [Enter] - выбор"

# Проверка наличия файла инвентаря
if [ ! -f "$INVENTORY_FILE" ]; then
    whiptail --title "Ошибка" --msgbox "Файл инвентаря '$INVENTORY_FILE' не найден!" 8 55
    exit 1
fi

# Кэш сессии для хранения параметров
last_user="" host="" user=""

# Список плейбуков (Индекс массива строго совпадает с номером пункта меню)
PLAYBOOKS=(
    "" # Нулевой индекс пропускаем, так как меню начинается с 1
    "init_vlab.yml"        # 1
    "create_user.yml"      # 2
    "delete_user.yml"      # 3
    "define_user_pool.yml" # 4
    "destroy_user_pool.yml" # 5
)

# Функция выбора хоста из инвентаря
select_host_from_inventory() {
    local mode=$1
    local menu_options=()
    [ "$mode" = "show_all" ] && menu_options+=("ALL" "Все хосты класса")

    while read -r name ip; do
        [ ! -z "$name" ] && [ ! -z "$ip" ] && menu_options+=("$name" "$ip")
    done < <(awk -F'[ =]' '$2 == "ansible_host" { print $1, $3 }' "$INVENTORY_FILE")

    host=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Выбрать" --cancel-button "Назад" --menu "Выберите целевой хост:" 18 65 10 "${menu_options[@]}" 3>&1 1>&2 2>&3) || return 1
    [ -z "$host" ] && return 1 || return 0
}

# Функция для запроса имени пользователя
prompt_user_name() {
    user=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Ввод" --cancel-button "Назад" --inputbox "Введите имя пользователя:" 10 55 "$last_user" 3>&1 1>&2 2>&3) || return 1
    [ -z "$user" ] && return 1 || { last_user="$user"; return 0; }
}

# Оптимизированная функция запуска Ansible
run_ansible() {
    local playbook=$1
    local current_user=$2
    local extra_vars=""

    clear
    
    # Шаг 1: Если выбран конкретный хост (не ALL), добавляем его в параметры
    [ "$host" != "ALL" ] && extra_vars="host=$host"
    
    # Шаг 2: Если передан пользователь (строка не пустая), добавляем его через пробел
    if [ -n "$current_user" ]; then
        [ -n "$extra_vars" ] && extra_vars="$extra_vars user=$current_user" || extra_vars="user=$current_user"
    fi

    # Шаг 3: Безопасный запуск. Если extra_vars пуст, ключ -e не подставится вовсе
    ansible-playbook "$playbook" ${extra_vars:+-e "$extra_vars"} || true
    
    read -n 1 -s -r -p "Нажмите любую клавишу..."
}

# Главный цикл панели управления
while true; do
    choice=$(whiptail --title "$TITLE" --backtitle "$HINT" --ok-button "Выбрать" --cancel-button "Выход" --menu "Выберите действие:" 15 65 5 \
        "1" "Инициализировать рабочее место" \
        "2" "Создать учетную запись пользователя" \
        "3" "Удалить учетную запись и пул виртуальных машин" \
        "4" "Создать пул виртуальных машин для пользователя" \
        "5" "Уничтожить пул виртуальных машин пользователя" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$choice" ]; then
        clear
        exit 0
    fi

    # Считываем имя плейбука по индексу выбранного пункта меню
    playbook="${PLAYBOOKS[$choice]}"
    
    # Интеллектуальное определение логики на основе имени плейбука
    if [[ "$playbook" == *"user"* ]]; then
        need_user=true
        inv_mode="hide_all"
    else
        need_user=false
        inv_mode="show_all"
    fi

    # Конвейер шагов интерфейса
    select_host_from_inventory "$inv_mode" || continue
    [ "$need_user" = true ] && { prompt_user_name || continue; }

    # Индивидуальное исключение для подтверждения удаления (пункт 3)
    if [ "$choice" -eq 3 ]; then
        whiptail --title "Подтверждение" --backtitle "$HINT" --ok-button "Да" --cancel-button "Нет" --yesno "Удалить пользователя '$user' на хосте '$host'?" 10 60 || continue
    fi

    # Запуск сценария с передачей имени пользователя или пустой строки
    if [ "$need_user" = true ]; then
        run_ansible "$playbook" "$user"
    else
        run_ansible "$playbook" ""
    fi
done
