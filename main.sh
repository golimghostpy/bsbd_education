#!/bin/bash

# Функция для вывода справки
show_help() {
    echo "Использование: $0 [--start|--stop|--clear]"
    echo ""
    echo "Опции:"
    echo "  --start   Запустить контейнеры в фоновом режиме"
    echo "  --stop    Остановить контейнеры"
    echo "  --clear   Удалить контейнеры и volumes"
    echo "  --help    Показать эту справку"
    echo ""
}

# Функция для запуска контейнеров
start_containers() {
    echo "Запуск контейнеров..."
    sudo docker compose up -d
    if [ $? -eq 0 ]; then
        echo "Контейнеры успешно запущены"
    else
        echo "Ошибка при запуске контейнеров" >&2
        exit 1
    fi
}

# Функция для остановки контейнеров
stop_containers() {
    echo "Остановка контейнеров..."
    sudo docker compose stop
    if [ $? -eq 0 ]; then
        echo "Контейнеры успешно остановлены"
    else
        echo "Ошибка при остановке контейнеров" >&2
        exit 1
    fi
}

# Функция для удаления контейнеров и volumes
clear_containers() {
    echo "Удаление контейнеров и volumes..."
    
    sudo docker compose stop
    
    sudo docker compose down -v
    if [ $? -eq 0 ]; then
        echo "Контейнеры и volumes успешно удалены"
    else
        echo "Ошибка при удалении контейнеров и volumes" >&2
        exit 1
    fi
}

# Проверка количества аргументов
if [ $# -ne 1 ]; then
    echo "Ошибка: необходимо указать один аргумент" >&2
    show_help
    exit 1
fi

# Обработка аргументов
case "$1" in
    --start|-s)
        start_containers
        ;;
    --stop)
        stop_containers
        ;;
    --clear|-c)
        clear_containers
        ;;
    --help)
        show_help
        ;;
    *)
        echo "Ошибка: неизвестный аргумент '$1'" >&2
        show_help
        exit 1
        ;;
esac
