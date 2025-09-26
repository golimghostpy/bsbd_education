#!/bin/bash

echo "Проверка CONNECT привилегии - Может ли PUBLIC подключаться к базе education_db?"
check_connect=$(sudo docker exec -i postgres psql -U test_connect -d education_db 2>&1)

if [ -n "$(echo "$check_connect" | grep -i "error")" ]; then
    echo "УСПЕХ!"
fi
