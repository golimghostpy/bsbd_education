#!/bin/bash

echo "Начинаем бэкап логов изменения таблиц за последние 30 дней"
echo ""

sudo docker exec -i postgres psql -h "localhost" -U "postgres" -d "education_db" -c "SELECT audit.backup_audit_logs(30);" 2>&1

echo ""
echo "Бэкап логов завершен"
