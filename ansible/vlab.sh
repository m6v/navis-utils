#!/usr/bin/env bash

# Скрипт-обертка vlab для управления виртуальной лабораторией учебного класса

# Прерывать выполнение при любой критической ошибке
set -e

usage() {
    echo "Использование:"
    echo "  $0 --init_class                             - Развертывание базовой инфраструктуры класса"
    echo "  $0 --init_user --user <имя> --host <хост>   - Создание рабочего места ученика"
    echo "  $0 --clean_user --user <имя> --host <хост>  - Очистка рабочего места ученика"
    exit 1
}

ACTION=""
USER_NAME=""
HOST_NAME=""

# Разбор аргументов командной строки
while [[ $# -gt 0 ]]; do
    case "$1" in
        --init_class|--init_user|--clean_user)
            if [[ -n "$ACTION" ]]; then
                echo "Ошибка: Можно указать только одно основное действие --init_class, --init_user или --clean_user"
                exit 1
            fi
            # Убрать ведущие дефисы
            ACTION="${1#--}"
            shift
            ;;
        --user)
            USER_NAME="$2"
            shift 2
            ;;
        --host)
            HOST_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Ошибка: Неизвестный параметр $1"
            usage
            ;;
    esac
done

# Валидация выбранного действия
if [[ -z "$ACTION" ]]; then
    echo "Ошибка: Не указано действие"
    usage
fi

# Выполнение логики в зависимости от действия
case "$ACTION" in
    init_class)
        echo "[vlab] Запуск развертывания инфраструктуры класса..."
        ansible-playbook init_class.yml
        ;;
        
    init_user|clean_user)
        # Проверка обязательных параметров для работы с пользователями
        if [[ -z "$USER_NAME" ]] || [[ -z "$HOST_NAME" ]]; then
            echo "Ошибка: Для действия --$ACTION обязательны параметры --user и --host"
            usage
        fi
        
        echo "[vlab] Запуск сценария $ACTION для пользователя $USER_NAME на хосте $HOST_NAME..."
        ansible-playbook "${ACTION}.yml" -e "host=${HOST_NAME} user=${USER_NAME}"
        ;;
esac
