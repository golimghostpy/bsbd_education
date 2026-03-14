#!/bin/bash

CONTAINER_NAME="postgres"
DB_USER="postgres"
DB_PASSWORD="1234qwer"

echo "=== Настройка SSL для PostgreSQL в Docker-контейнере ==="

echo -n "Хотите перегенерировать SSL сертификаты? (y/N): "
read -r regenerate_certificates < /dev/tty

regenerate_certificates=$(echo "$regenerate_certificates" | tr '[:upper:]' '[:lower:]')

if [[ "$regenerate_certificates" == "y" || "$regenerate_certificates" == "Y" ]]; then
    echo "Очистка старых сертификатов..."
    rm -f server.crt server.key

    echo "1. Генерация SSL сертификата и ключа..."
    openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes -subj "/CN=postgres" 2>/dev/null

    echo "2. Копирование сертификатов в контейнер..."
    docker cp server.crt $CONTAINER_NAME:/tmp/
    docker cp server.key $CONTAINER_NAME:/tmp/

    echo "3. Создание директории SSL и установка прав..."
    docker exec -it $CONTAINER_NAME bash -c "
      mkdir -p /etc/postgresql/ssl && \
      cp /tmp/server.crt /etc/postgresql/ssl/ && \
      cp /tmp/server.key /etc/postgresql/ssl/ && \
      chmod 600 /etc/postgresql/ssl/server.key && \
      chown postgres:postgres /etc/postgresql/ssl/server.key && \
      chmod 644 /etc/postgresql/ssl/server.crt && \
      chown postgres:postgres /etc/postgresql/ssl/server.crt && \
      rm /tmp/server.crt /tmp/server.key
    "

    rm -f server.crt server.key ssl.conf

    echo "4. Настройка postgresql.conf..."
    docker exec -it $CONTAINER_NAME bash -c "
      echo \"ssl = on\" >> /var/lib/postgresql/data/postgresql.conf && \
      echo \"ssl_cert_file = '/etc/postgresql/ssl/server.crt'\" >> /var/lib/postgresql/data/postgresql.conf && \
      echo \"ssl_key_file = '/etc/postgresql/ssl/server.key'\" >> /var/lib/postgresql/data/postgresql.conf
    "

    echo "5. Настройка pg_hba.conf для требования SSL..."
    docker exec -it $CONTAINER_NAME bash -c "
      # Резервное копирование оригинального файла
      cp /var/lib/postgresql/data/pg_hba.conf /var/lib/postgresql/data/pg_hba.conf.backup
      
      # Создание нового pg_hba.conf с SSL требованиями
      cat > /var/lib/postgresql/data/pg_hba.conf << EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     scram-sha-256
hostssl all             all             0.0.0.0/0               scram-sha-256
hostssl all             all             ::/0                    scram-sha-256
EOF
    "

    echo "6. Перезапуск PostgreSQL..."
    docker restart $CONTAINER_NAME

    echo "7. Ожидание запуска PostgreSQL..."
    sleep 5

    echo "Сертификаты успешно перегенерированы и настроены."
else
    echo "Пропуск генерации сертификатов. Используются существующие сертификаты в контейнере."
fi

echo "=== Подключение с SSL ==="
psql "host=localhost port=5432 dbname=education_db user=postgres password=1234qwer sslmode=require" -c "\conninfo"

echo -e "\n=== Подключение БЕЗ SSL ==="
psql "host=localhost port=5432 dbname=education_db user=postgres password=1234qwer sslmode=disable" -c "\conninfo"

echo "=== Настройка SSL завершена ==="