#!/bin/bash

# Цвета
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

check_connection() {
    check_connect=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db 2>&1)

    if [ -n "$(echo "$check_connect" | grep -i "error")" ]; then
        echo -e "${GREEN}УСПЕХ!${NC}"
    else
        echo -e "${RED}ОШИБКА${NC}"
        echo $check_connect
    fi
}

# Функция для выдачи и отзыва ролей
manage_role() {
    local action=$1
    local role=$2
    if [ "$action" = "GRANT" ]; then
        sudo docker exec -i postgres psql -h localhost -U postgres -d education_db -c "GRANT $role TO test_connect;" 2>&1
    else
        sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE $role FROM test_connect;" 2>&1
    fi
}

# Функция для проверки выполнения команды (разрешенные операции)
check_command() {
    local command=$1
    local test_name=$2
    local expected_result=$3  # "success" или "error"
    
    if [ -z "$expected_result" ]; then
        expected_result="success"
    fi
    
    echo "Тестирование: $test_name"
    result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "$command" 2>&1)
    
    if [ "$expected_result" = "success" ]; then
        if [ -z "$(echo "$result" | grep -i "error")" ]; then
            echo -e "${GREEN}+++ УСПЕХ: Команда выполнена (как и ожидалось)${NC}"
        else
            echo -e "${RED}--- ОШИБКА: Команда не выполнена (но должна была)${NC}"
            echo "$result"
        fi
    else
        if [ -n "$(echo "$result" | grep -i "error")" ]; then
            echo -e "${GREEN}+++ УСПЕХ: Команда отклонена (как и ожидалось)${NC}"
        else
            echo -e "${RED}--- ОШИБКА: Команда выполнена (но не должна была)${NC}"
            echo "$result"
        fi
    fi
    echo ""
}

check_audit() {
    check_audit_result=$(sudo docker exec -i postgres psql -h localhost -U postgres -d education_db -c "SELECT username FROM audit.login_log" 2>&1)

    if [ $(echo "$check_audit_result" | wc -l) -gt 5 ]; then
        echo -e "${GREEN}УСПЕХ!${NC}"
        echo "$check_audit_result" | head -n 5
    else
        echo -e "${RED}ОШИБКА${NC}"
        echo "$check_audit_result"
    fi
}

# Функция для подготовки тестовых данных
prepare_test_data() {
    echo "Подготовка тестовых данных..."
    sudo docker exec -i postgres psql -U postgres -d education_db << EOF
    -- Создаем цепочку тестовых данных: educational_institutions -> faculties -> study_groups
    INSERT INTO ref.educational_institutions (institution_name, short_name, legal_address) 
    VALUES ('Тестовый Университет', 'ТУ', 'Тестовый адрес') 
    ON CONFLICT (institution_name) DO NOTHING;
    
    INSERT INTO ref.faculties (faculty_name, institution_id) 
    VALUES ('Тестовый Факультет', (SELECT institution_id FROM ref.educational_institutions WHERE institution_name = 'Тестовый Университет')) 
    ON CONFLICT (faculty_id) DO NOTHING;
    
    INSERT INTO ref.study_groups (group_name, admission_year, faculty_id) 
    VALUES ('TEST-01', 2024, (SELECT faculty_id FROM ref.faculties WHERE faculty_name = 'Тестовый Факультет')) 
    ON CONFLICT (group_id) DO NOTHING;
    
    -- Создаем тестового студента для операций UPDATE/DELETE
    INSERT INTO app.students (last_name, first_name, student_card_number, group_id) 
    SELECT 'Тестов', 'test1', 'TEST001', group_id 
    FROM ref.study_groups 
    WHERE group_name = 'TEST-01' 
    AND NOT EXISTS (SELECT 1 FROM app.students WHERE student_card_number = 'TEST001');
    
    -- Создаем тестовую таблицу для аудита
    INSERT INTO audit.login_log (username, client_ip) 
    VALUES ('test_user', '192.168.1.1')
    ON CONFLICT DO NOTHING;
EOF
}

# Функция для очистки тестовых данных
cleanup_test_data() {
    echo "Очистка тестовых данных..."
    sudo docker exec -i postgres psql -U postgres -d education_db << EOF
    DELETE FROM app.students WHERE student_card_number LIKE 'TEST%';
    DELETE FROM ref.study_groups WHERE group_name = 'TEST-01';
    DELETE FROM ref.faculties WHERE faculty_name = 'Тестовый Факультет';
    DELETE FROM ref.educational_institutions WHERE institution_name = 'Тестовый Университет';
    DELETE FROM audit.login_log WHERE username = 'test_user';
    DROP TABLE IF EXISTS app.test_table, app.unauthorized_table, ref.unauthorized_ref_table;
    DROP TABLE IF EXISTS audit.unauthorized_audit_table;
EOF
}

echo -e "${YELLOW}=== Тестирование подключения без роли ===${NC}"
check_connection
echo -e "${YELLOW}=== Конец тестирования подключения ===${NC}"
echo ""

echo -e "${YELLOW}=== Начало тестирования привилегий ===${NC}"
echo ""

echo "Выдаем право CONNECT пользователю test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT CONNECT ON DATABASE education_db TO test_connect;" 2>&1

# Подготовка тестовых данных
prepare_test_data

# 1. Тестирование роли app_reader
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_reader ===${NC}"
manage_role "GRANT" "app_reader"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT * FROM app.students LIMIT 1;" "app_reader: SELECT в схеме app" "success"
check_command "SELECT * FROM ref.faculties LIMIT 1;" "app_reader: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id) VALUES ('Тестов', 'test3', 'TEST003', 1);" "app_reader: INSERT в схеме app" "error"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "app_reader: CREATE TABLE в схеме app" "error"
check_command "SELECT * FROM audit.login_log LIMIT 1;" "app_reader: SELECT в схеме audit" "error"

manage_role "REVOKE" "app_reader"

# 2. Тестирование роли app_writer  
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_writer ===${NC}"
manage_role "GRANT" "app_writer"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id) VALUES ('Тестов', 'test2', 'TEST002', 1);" "app_writer: INSERT в схеме app" "success"
check_command "SELECT * FROM ref.faculties LIMIT 1;" "app_writer: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "app_writer: CREATE TABLE в схеме app" "error"
check_command "SELECT * FROM audit.login_log LIMIT 1;" "app_writer: SELECT в схеме audit" "error"

manage_role "REVOKE" "app_writer"

# 3. Тестирование роли app_owner
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_owner ===${NC}"
manage_role "GRANT" "app_owner"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "DELETE FROM app.students WHERE student_card_number = 'TEST002';" "app_owner: DELETE в схеме app" "success"
check_command "CREATE TABLE app.test_table (id serial, name text);" "app_owner: CREATE TABLE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE ref.unauthorized_ref_table (id serial);" "app_owner: CREATE TABLE в схеме ref" "error"
check_command "SELECT * FROM audit.login_log LIMIT 1;" "app_owner: SELECT в схеме audit" "error"

manage_role "REVOKE" "app_owner"

# 4. Тестирование роли auditor
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ auditor ===${NC}"
manage_role "GRANT" "auditor"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT * FROM audit.login_log LIMIT 1;" "auditor: SELECT в схеме audit" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "auditor: INSERT в схеме audit" "error"
check_command "CREATE TABLE audit.unauthorized_table (id serial);" "auditor: CREATE TABLE в схеме audit" "error"

manage_role "REVOKE" "auditor"

# 5. Тестирование роли ddl_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ddl_admin ===${NC}"
manage_role "GRANT" "ddl_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "CREATE TABLE app.test_table1 (id serial, name text);" "ddl_admin: CREATE TABLE в схеме app" "success"
check_command "ALTER TABLE app.test_table ADD COLUMN description text;" "ddl_admin: ALTER TABLE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id) VALUES ('Неавторизованный', 'test', 'TESTDDL', (SELECT group_id FROM ref.study_groups WHERE group_name = 'TEST-01'));" "ddl_admin: INSERT в таблицу" "error"

# Очистка тестовых таблиц DDL администратора
sudo docker exec -i postgres psql -U postgres -d education_db -c "DROP TABLE IF EXISTS app.test_table, ref.test_ref_table, audit.test_audit_table;" 2>&1

manage_role "REVOKE" "ddl_admin"

# 6. Тестирование роли dml_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ dml_admin ===${NC}"
manage_role "GRANT" "dml_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "UPDATE app.students SET last_name = 'Updated' WHERE student_card_number = 'TEST001';" "dml_admin: UPDATE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "dml_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "dml_admin: INSERT в схеме audit" "error"
check_command "SELECT * FROM audit.login_log LIMIT 1;" "dml_admin: SELECT в схеме audit (через роль auditor)" "error"

manage_role "REVOKE" "dml_admin"

# 7. Тестирование роли security_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ security_admin ===${NC}"
manage_role "GRANT" "security_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT rolname FROM pg_roles LIMIT 5;" "security_admin: SELECT из pg_roles" "success"
check_command "SET ROLE security_admin; CREATE ROLE test_role_123; DROP ROLE test_role_123;" "security_admin: CREATE ROLE с SET ROLE" "success" # используем SET ROLE т.к. свойство CREATEROLE не наследуется

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "security_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id) VALUES ('Тестов', 'test4', 'TEST004', 1);" "security_admin: INSERT в схеме app" "error"

manage_role "REVOKE" "security_admin"

# Очистка тестовых данных
cleanup_test_data

# Забираем право CONNECT в конце
echo "Забираем право CONNECT у пользователя test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE CONNECT ON DATABASE education_db FROM test_connect;" 2>&1

echo -e "${YELLOW}=== Конец тестирования привилегий ===${NC}"

echo -e "${YELLOW}=== Тестирование audit.login_log ===${NC}"
check_audit
echo -e "${YELLOW}=== Конец тестирования аудита ===${NC}"
