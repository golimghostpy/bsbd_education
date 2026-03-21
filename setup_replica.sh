#!/bin/bash

CONTAINER_NAME="postgres"
DB_USER="postgres"
DB_PASSWORD="1234qwer"
ARCHIVE_DIR="/var/lib/postgresql/archive"
PG_DATA_DIR="/var/lib/postgresql/data"

echo "=== Настройка WAL-архивирования и репликации для PostgreSQL ==="

# Проверяем, запущен ли контейнер
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "Ошибка: Контейнер $CONTAINER_NAME не запущен"
    exit 1
fi

# Создаем директорию для архивов внутри контейнера
echo "1. Создание директории для WAL-архивов..."
docker exec -it $CONTAINER_NAME bash -c "
    mkdir -p $ARCHIVE_DIR && \
    chown postgres:postgres $ARCHIVE_DIR && \
    chmod 750 $ARCHIVE_DIR
"

# Создаем скрипт для архивирования с шифрованием внутри контейнера
echo "2. Создание скрипта архивирования с шифрованием..."
docker exec -it $CONTAINER_NAME bash -c "
cat > /usr/local/bin/archive_wal.sh << 'EOF'
#!/bin/bash
# Скрипт для архивирования WAL с шифрованием
# Параметры: %p - полный путь к WAL файлу, %f - имя файла

WAL_PATH=\"\$1\"
WAL_NAME=\"\$2\"
ARCHIVE_DIR=\"$ARCHIVE_DIR\"
PASSWORD=\"${DB_PASSWORD}\"

# Проверяем, что WAL файл существует
if [ ! -f \"\$WAL_PATH\" ]; then
    echo \"Ошибка: WAL файл \$WAL_PATH не найден\" >&2
    exit 1
fi

# Архивируем и шифруем WAL файл (упрощенный вариант для лабораторной работы)
gzip < \"\$WAL_PATH\" | openssl enc -aes-256-cbc -pass pass:\"\$PASSWORD\" -out \"\$ARCHIVE_DIR/\${WAL_NAME}.gz.enc\"

# Проверяем успешность операции
if [ \$? -eq 0 ]; then
    exit 0
else
    echo \"Ошибка при архивировании/шифровании: \$WAL_NAME\" >&2
    exit 1
fi
EOF

chmod +x /usr/local/bin/archive_wal.sh
chown postgres:postgres /usr/local/bin/archive_wal.sh
"

# Бэкап текущей конфигурации
echo "3. Создание резервной копии postgresql.conf..."
docker exec -it $CONTAINER_NAME bash -c "
    cp $PG_DATA_DIR/postgresql.conf $PG_DATA_DIR/postgresql.conf.backup_\$(date +%Y%m%d_%H%M%S)
"

# Настройка postgresql.conf
echo "4. Настройка postgresql.conf для репликации и архивирования..."
docker exec -it $CONTAINER_NAME bash -c "
    # Удаляем старые настройки если есть
    sed -i '/^wal_level/d' $PG_DATA_DIR/postgresql.conf
    sed -i '/^archive_mode/d' $PG_DATA_DIR/postgresql.conf
    sed -i '/^archive_command/d' $PG_DATA_DIR/postgresql.conf
    sed -i '/^max_wal_senders/d' $PG_DATA_DIR/postgresql.conf
    sed -i '/^wal_keep_size/d' $PG_DATA_DIR/postgresql.conf
    sed -i '/^hot_standby/d' $PG_DATA_DIR/postgresql.conf
    
    # Добавляем новые настройки
    cat >> $PG_DATA_DIR/postgresql.conf << EOL

# Настройки репликации и архивирования
wal_level = replica
archive_mode = on
archive_command = '/usr/local/bin/archive_wal.sh %p %f'
max_wal_senders = 10
wal_keep_size = 64
hot_standby = on
EOL
"

# Настройка pg_hba.conf для репликации
echo "5. Настройка pg_hba.conf для репликации..."
docker exec -it $CONTAINER_NAME bash -c "
    # Создаем резервную копию
    cp $PG_DATA_DIR/pg_hba.conf $PG_DATA_DIR/pg_hba.conf.backup_\$(date +%Y%m%d_%H%M%S)
    
    # Добавляем правило для репликации, если его еще нет
    if ! grep -q '^host\s\+replication' $PG_DATA_DIR/pg_hba.conf; then
        echo '' >> $PG_DATA_DIR/pg_hba.conf
        echo '# Репликация' >> $PG_DATA_DIR/pg_hba.conf
        echo 'host replication all 0.0.0.0/0 scram-sha-256' >> $PG_DATA_DIR/pg_hba.conf
        echo 'host replication all ::/0 scram-sha-256' >> $PG_DATA_DIR/pg_hba.conf
    fi
"

# Создание пользователя для репликации (если не существует)
echo "6. Создание пользователя для репликации..."
docker exec -it $CONTAINER_NAME bash -c "
    PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d postgres -c \"SELECT 1 FROM pg_roles WHERE rolname='replicator'\" | grep -q 1 || \
    PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d postgres -c \"CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password'\"
"

# Перезапуск PostgreSQL от имени пользователя postgres с полным путем
echo "7. Перезапуск PostgreSQL для применения настроек..."
docker exec -it $CONTAINER_NAME bash -c "
    su - postgres -c \"/usr/lib/postgresql/17/bin/pg_ctl -D $PG_DATA_DIR -m fast -w restart\"
"

echo
echo "=== Настройка репликации и архивирования завершена ==="

echo "Итоговые настройки:"
docker exec -it postgres psql -U postgres -d education_db -c "
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN ('wal_level', 'archive_mode', 'archive_command', 'max_wal_senders', 'wal_keep_size', 'hot_standby');
"

echo "Тестовое создание архива WAL"
docker exec -it postgres bash -c "
# Переключаем WAL
PGPASSWORD=1234qwer psql -U postgres -d postgres -c \"SELECT pg_switch_wal();\" 2>/dev/null
sleep 2
# Проверяем содержимое директории архивов
echo '--- Файлы в директории архива ---'
ls -lah /var/lib/postgresql/archive/
"