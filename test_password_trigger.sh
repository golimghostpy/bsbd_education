#!/bin/bash

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для выполнения команд
docker_psql() {
    sudo docker exec -i postgres psql -U postgres -d education_db "$@"
}

docker_psql_user() {
    local user=$1
    shift
    sudo docker exec -i postgres psql -U "$user" -d education_db "$@"
}

test_password_protection() {
    echo -e "${YELLOW}=== ТЕСТИРОВАНИЕ ТРИГГЕРА НА ОГРАНИЧЕНИЕ СМЕНЫ ПАРОЛЕЙ ===${NC}\n"

    # ПОДГОТОВКА
    echo -e "${BLUE}--- Подготовка тестовых данных ---${NC}"
    docker_psql -c "
        -- Сначала сбрасываем все права test_connect
        REVOKE security_admin FROM test_connect;
        REVOKE app_owner FROM test_connect;
        
        -- Создаем тестового пользователя
        DROP USER IF EXISTS test_employee;
        CREATE USER test_employee WITH PASSWORD 'initial_pass';
        GRANT CONNECT ON DATABASE education_db TO test_employee;
        
        -- Очищаем таблицы
        DELETE FROM app.employees WHERE username = 'test_employee';
        DELETE FROM app.password_change_allowance WHERE username = 'test_employee';
        DELETE FROM audit.function_calls WHERE function_name LIKE 'password_%' OR function_name = 'change_employee_password';
        
        -- Добавляем тестового сотрудника
        INSERT INTO app.employees (username, password_hash, full_name)
        SELECT 'test_employee', public.crypt('initial_pass', public.gen_salt('bf')), 'Тестовый Сотрудник';
        
        -- Настраиваем права для test_connect (только app_owner для начала)
        GRANT app_owner TO test_connect;
        GRANT USAGE ON SCHEMA app, audit TO test_connect;
        GRANT EXECUTE ON FUNCTION app.change_employee_password(VARCHAR(100), TEXT) TO app_owner;
        GRANT EXECUTE ON FUNCTION app.grant_temp_password_change(VARCHAR(100), INTEGER) TO security_admin;
    " > /dev/null 2>&1
    echo -e "${GREEN}✓ База данных подготовлена (test_employee создан, test_connect имеет роль app_owner)${NC}\n"

    # ТЕСТ 1: Прямое обновление таблицы (должно быть запрещено)
    echo -e "${BLUE}--- ТЕСТ 1: Прямое UPDATE таблицы employees (без разрешения) ---${NC}"
    echo -e "  ${YELLOW}▶ Отзываем security_admin, оставляем только app_owner${NC}"
    
    docker_psql -c "REVOKE security_admin FROM test_connect;" > /dev/null 2>&1

    echo -e "  ${YELLOW}▶ Текущие права test_connect:${NC}"
    docker_psql -c "
        SELECT r.rolname, 
               array(SELECT b.rolname FROM pg_auth_members m JOIN pg_roles b ON m.roleid = b.oid WHERE m.member = r.oid) as member_of
        FROM pg_roles r 
        WHERE r.rolname = 'test_connect';
    " 2>&1 | grep -v "row" | sed 's/^/    /'

    echo -e "  ${YELLOW}▶ Пытаемся выполнить UPDATE таблицы employees напрямую...${NC}"
    result=$(docker_psql_user test_connect -c "
        BEGIN;
        UPDATE app.employees 
        SET password_hash = public.crypt('hacked', public.gen_salt('bf'))
        WHERE username = 'test_employee'
        RETURNING username, updated_by;
        ROLLBACK;
    " 2>&1)

    if [ -n "$(echo "$result" | grep -i "error")" ]; then
        echo -e "  ${GREEN}✓ УСПЕХ: Триггер сработал! Получена ошибка:${NC}"
        echo -e "    ${RED}$(echo "$result" | grep -o "ERROR:.*" | head -1)${NC}"
    else
        echo -e "  ${RED}✗ ОШИБКА: Команда выполнилась без ошибок (триггер не сработал)${NC}"
        echo "Результат:"
        echo "$result" | grep -v "ROLLBACK" | grep -v "BEGIN" | sed 's/^/    /'
    fi
    echo ""

    # Возвращаем security_admin для следующих тестов
    docker_psql -c "GRANT security_admin TO test_connect;" > /dev/null 2>&1

    # ТЕСТ 2: Смена пароля через функцию БЕЗ разрешения
    echo -e "${BLUE}--- ТЕСТ 2: Смена пароля через функцию change_employee_password (без разрешения) ---${NC}"
    echo -e "  ${YELLOW}▶ Отзываем security_admin, оставляем только app_owner${NC}"
    
    docker_psql -c "REVOKE security_admin FROM test_connect;" > /dev/null 2>&1
    
    echo -e "  ${YELLOW}▶ Вызываем app.change_employee_password('test_employee', 'new_pass')${NC}"
    result=$(docker_psql_user test_connect -c "SELECT app.change_employee_password('test_employee', 'new_pass');" 2>&1)
    
    if [ -n "$(echo "$result" | grep -i "error")" ]; then
        echo -e "  ${GREEN}✓ УСПЕХ: Функция запретила смену пароля:${NC}"
        echo -e "    ${RED}$(echo "$result" | grep -o "ERROR:.*" | head -1)${NC}"
    else
        echo -e "  ${RED}✗ ОШИБКА: Функция выполнилась (должна была запретить)${NC}"
        echo "$result" | sed 's/^/    /'
    fi
    echo ""

    # ТЕСТ 3: Смена пароля security_admin'ом
    echo -e "${BLUE}--- ТЕСТ 3: Смена пароля security_admin'ом ---${NC}"
    echo -e "  ${YELLOW}▶ Выдаем роль security_admin test_connect${NC}"
    
    docker_psql -c "GRANT security_admin TO test_connect;" > /dev/null 2>&1
    
    echo -e "  ${YELLOW}▶ Текущие права test_connect (есть security_admin):${NC}"
    docker_psql -c "
        SELECT r.rolname, 
               array(SELECT b.rolname FROM pg_auth_members m JOIN pg_roles b ON m.roleid = b.oid WHERE m.member = r.oid) as member_of
        FROM pg_roles r 
        WHERE r.rolname = 'test_connect';
    " 2>&1 | grep -v "row" | sed 's/^/    /'
    
    echo -e "  ${YELLOW}▶ Вызываем app.change_employee_password('test_employee', 'admin_pass')${NC}"
    result=$(docker_psql_user test_connect -c "SELECT app.change_employee_password('test_employee', 'admin_pass');" 2>&1)
    
    if [ -z "$(echo "$result" | grep -i "error")" ]; then
        echo -e "  ${GREEN}✓ УСПЕХ: Пароль изменен через функцию (security_admin имеет право)${NC}"
        echo -e "    Результат: ${result//[^a-zA-Z0-9 ]/}"
    else
        echo -e "  ${RED}✗ ОШИБКА: ${result}${NC}"
    fi
    echo ""

    # ТЕСТ 4: Временное разрешение на смену пароля
    echo -e "${BLUE}--- ТЕСТ 4: Временное разрешение на смену пароля ---${NC}"
    echo -e "  ${YELLOW}▶ Отзываем security_admin (остается только app_owner)${NC}"
    
    docker_psql -c "REVOKE security_admin FROM test_connect;" > /dev/null 2>&1

    echo -e "  ${YELLOW}▶ Выдаем временное разрешение (нужен security_admin для выдачи)${NC}"
    docker_psql -c "GRANT security_admin TO test_connect;" > /dev/null 2>&1
    docker_psql_user test_connect -c "SELECT app.grant_temp_password_change('test_employee', 1);" > /dev/null 2>&1
    docker_psql -c "REVOKE security_admin FROM test_connect;" > /dev/null 2>&1
    
    echo -e "  ${YELLOW}▶ Проверяем, что разрешение создалось:${NC}"
    docker_psql -c "
        SELECT username, expires_at, is_used 
        FROM app.password_change_allowance 
        WHERE username = 'test_employee';
    " 2>&1 | grep -v "row" | sed 's/^/    /'
    
    echo -e "  ${YELLOW}▶ Пытаемся сменить пароль с временным разрешением${NC}"
    result=$(docker_psql_user test_connect -c "SELECT app.change_employee_password('test_employee', 'temp_pass');" 2>&1)
    
    if [ -z "$(echo "$result" | grep -i "error")" ]; then
        echo -e "  ${GREEN}✓ УСПЕХ: Пароль изменен с временным разрешением${NC}"
        echo -e "    Результат: ${result//[^a-zA-Z0-9 ]/}"
        
        echo -e "  ${YELLOW}▶ Проверяем, что разрешение помечено как использованное:${NC}"
        docker_psql -c "
            SELECT username, expires_at, is_used 
            FROM app.password_change_allowance 
            WHERE username = 'test_employee';
        " 2>&1 | grep -v "row" | sed 's/^/    /'
    else
        echo -e "  ${RED}✗ ОШИБКА: ${result}${NC}"
    fi
    echo ""

    # ТЕСТ 5: Проверка подключения с новым паролем
    echo -e "${BLUE}--- ТЕСТ 5: Проверка подключения с новым паролем ---${NC}"
    echo -e "  ${YELLOW}▶ Пробуем подключиться к БД с паролем 'temp_pass'${NC}"
    
    export PGPASSWORD='temp_pass'
    connect_result=$(psql -h localhost -U test_employee -d education_db -c "SELECT current_user, current_database();" 2>&1)
    unset PGPASSWORD
    
    if [ -n "$(echo "$connect_result" | grep "test_employee")" ]; then
        echo -e "  ${GREEN}✓ УСПЕХ: Подключение выполнено:${NC}"
        echo "$connect_result" | grep -v "row" | sed 's/^/    /'
    else
        echo -e "  ${RED}✗ ОШИБКА: Не удалось подключиться${NC}"
        echo "$connect_result" | sed 's/^/    /'
    fi
    echo ""

    # ОЧИСТКА
    echo -e "${BLUE}--- Очистка тестовых данных ---${NC}"
    docker_psql -c "
        DROP USER IF EXISTS test_employee;
        DELETE FROM app.employees WHERE username = 'test_employee';
        DELETE FROM app.password_change_allowance WHERE username = 'test_employee';
        REVOKE security_admin FROM test_connect;
        REVOKE app_owner FROM test_connect;
    " > /dev/null 2>&1
    echo -e "${GREEN}✓ Все тестовые данные удалены${NC}\n"

    echo -e "${YELLOW}=== ТЕСТИРОВАНИЕ ЗАВЕРШЕНО УСПЕШНО ===${NC}"
}

# Запуск
test_password_protection