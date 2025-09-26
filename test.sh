#!/bin/bash

# Цвета
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_connection() {
    check_connect=$(sudo docker exec -i postgres psql -U test_connect -d education_db 2>&1)

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
        sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT $role TO test_connect;" 2>&1
    else
        sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE $role FROM test_connect;" 2>&1
    fi
}

# Функция для проверки выполнения команды
check_command() {
    local command=$1
    local test_name=$2
    
    echo "Тестирование: $test_name"
    result=$(sudo docker exec -i postgres psql -U test_connect -d education_db -c "$command" 2>&1)
    
    if [ -z "$(echo "$result" | grep -i "error")" ]; then
        echo -e "${GREEN}+++ УСПЕХ: Команда выполнена${NC}"
    else
        echo -e "${RED}--- ОШИБКА: Команда не выполнена${NC}"
        echo "$result"
    fi
    echo ""
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
check_command "SELECT * FROM app.students LIMIT 1;" "app_reader: SELECT в схеме app"
manage_role "REVOKE" "app_reader"

# 2. Тестирование роли app_writer  
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_writer ===${NC}"
manage_role "GRANT" "app_writer"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id) VALUES ('Тестов', 'test2', 'TEST002', (SELECT group_id FROM ref.study_groups WHERE group_name = 'TEST-01'));" "app_writer: INSERT в схеме app"
manage_role "REVOKE" "app_writer"

# 3. Тестирование роли app_owner
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_owner ===${NC}"
manage_role "GRANT" "app_owner"
check_command "DELETE FROM app.students WHERE student_card_number = 'TEST002';" "app_owner: DELETE в схеме app"
manage_role "REVOKE" "app_owner"

# 4. Тестирование роли auditor
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ auditor ===${NC}"
manage_role "GRANT" "auditor"
check_command "SELECT * FROM audit.login_log LIMIT 1;" "auditor: SELECT в схеме audit"
manage_role "REVOKE" "auditor"

# 5. Тестирование роли ddl_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ddl_admin ===${NC}"
manage_role "GRANT" "ddl_admin"
check_command "CREATE TABLE app.test_table (id serial, name text);" "ddl_admin: CREATE TABLE в схеме app"
sudo docker exec -i postgres psql -U postgres -d education_db -c "DROP TABLE IF EXISTS app.test_table;" 2>&1
manage_role "REVOKE" "ddl_admin"

# 6. Тестирование роли dml_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ dml_admin ===${NC}"
manage_role "GRANT" "dml_admin"
check_command "UPDATE app.students SET last_name = 'Updated' WHERE student_card_number = 'TEST001';" "dml_admin: UPDATE в схеме app"
manage_role "REVOKE" "dml_admin"

# 7. Тестирование роли security_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ security_admin ===${NC}"
manage_role "GRANT" "security_admin"
check_command "SELECT rolname FROM pg_roles LIMIT 5;" "security_admin: SELECT из pg_roles"
manage_role "REVOKE" "security_admin"

# Очистка тестовых данных
cleanup_test_data

# Забираем право CONNECT в конце
echo "Забираем право CONNECT у пользователя test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE CONNECT ON DATABASE education_db FROM test_connect;" 2>&1

echo -e "${YELLOW}=== Конец тестирования привилегий ===${NC}"