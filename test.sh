#!/bin/bash

# Цвета
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для создания тестовых ролей с сегментами
create_test_roles() {
    echo "Создание тестовых ролей с сегментами..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Создаем тестовые сегменты
    INSERT INTO ref.segments (segment_id, segment_name, description) VALUES 
    (1000, 'Тестовый Университет 1000', 'Тестовый сегмент для тестирования'),
    (1001, 'Тестовый Университет 1001', 'Другой тестовый сегмент')
    ON CONFLICT (segment_id) DO NOTHING;
    
    -- Создаем тестовые роли для сегмента 1000
    DO $$ 
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_reader_1000') THEN
            CREATE ROLE test_reader_1000;
            GRANT app_reader TO test_reader_1000;
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_writer_1000') THEN
            CREATE ROLE test_writer_1000;
            GRANT app_writer TO test_writer_1000;
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_reader_1001') THEN
            CREATE ROLE test_reader_1001;
            GRANT app_reader TO test_reader_1001;
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_writer_1001') THEN
            CREATE ROLE test_writer_1001;
            GRANT app_writer TO test_writer_1001;
        END IF;
    END $$;
    
    -- Добавляем роли в таблицу сопоставления
    INSERT INTO app.role_segments (role_name, segment_id) VALUES
    ('test_reader_1000', 1000),
    ('test_writer_1000', 1000),
    ('test_reader_1001', 1001),
    ('test_writer_1001', 1001)
    ON CONFLICT (role_name) DO UPDATE SET segment_id = EXCLUDED.segment_id;
EOF
}

# Функция для подготовки тестовых данных с учетом сегментации
prepare_test_data() {
    echo "Подготовка тестовых данных с сегментацией..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Создаем тестовые учебные заведения
    INSERT INTO app.educational_institutions (institution_id, institution_name, short_name, legal_address, segment_id) VALUES 
    (1000, 'Тестовый Университет 1000', 'ТУ1000', 'Тестовый адрес 1000', 1000),
    (1001, 'Тестовый Университет 1001', 'ТУ1001', 'Тестовый адрес 1001', 1001)
    ON CONFLICT (institution_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовые факультеты
    INSERT INTO app.faculties (faculty_id, faculty_name, institution_id, segment_id) VALUES 
    (1000, 'Тестовый Факультет 1000', 1000, 1000),
    (1001, 'Тестовый Факультет 1001', 1001, 1001)
    ON CONFLICT (faculty_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовые группы
    INSERT INTO app.study_groups (group_id, group_name, admission_year, faculty_id, segment_id) VALUES 
    (1000, 'TEST-1000', 2024, 1000, 1000),
    (1001, 'TEST-1001', 2024, 1001, 1001)
    ON CONFLICT (group_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовых преподавателей
    INSERT INTO app.teachers (teacher_id, last_name, first_name, academic_degree, academic_title, segment_id) VALUES 
    (1000, 'Тестовый1000', 'Преподаватель1000', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1000),
    (1001, 'Тестовый1001', 'Преподаватель1001', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1001)
    ON CONFLICT (teacher_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовых студентов
    INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) VALUES 
    (1000, 'Студент1000', 'Тестов1000', 'TEST1000', 1000, 1000, 'student1000@test.ru'),
    (1001, 'Студент1001', 'Тестов1001', 'TEST1001', 1001, 1001, 'student1001@test.ru')
    ON CONFLICT (student_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовые документы
    INSERT INTO app.student_documents (student_id, document_type, document_number, segment_id) VALUES 
    (1000, 'Паспорт'::public.document_type_enum, 'PASS1000', 1000),
    (1001, 'Паспорт'::public.document_type_enum, 'PASS1001', 1001)
    ON CONFLICT DO NOTHING;
EOF
}

check_connection() {
    check_connect=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db 2>&1)

    if [ -n "$(echo "$check_connect" | grep -i "error")" ]; then
        echo -e "${GREEN}УСПЕХ! Доступ ограничен${NC}"
    else
        echo -e "${RED}ОШИБКА. Предоставлен доступ${NC}"
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

# Функция для проверки количества строк в результате
check_row_count() {
    local command=$1
    local test_name=$2
    local expected_count=$3
    
    echo "Тестирование: $test_name"
    result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -t -c "$command" 2>&1)
    row_count=$(echo "$result" | grep -v '^$' | wc -l)
    
    if [ "$row_count" -eq "$expected_count" ]; then
        echo -e "${GREEN}+++ УСПЕХ: Найдено $row_count строк (ожидалось $expected_count)${NC}"
        return 0
    else
        echo -e "${RED}--- ОШИБКА: Найдено $row_count строк (ожидалось $expected_count)${NC}"
        echo "Результат: $result"
        return 1
    fi
}

check_audit() {
    check_audit_result=$(sudo docker exec -i postgres psql -h localhost -U postgres -d education_db -c "SELECT username FROM audit.login_log" 2>&1)

    if [ $(echo "$check_audit_result" | wc -l) -gt 5 ]; then
        echo -e "${GREEN}УСПЕХ!${NC}"
        echo "$check_audit_result" | head -n 7
    else
        echo -e "${RED}ОШИБКА${NC}"
        echo "$check_audit_result"
    fi
}

# Функция для проверки выполнения команды функций
check_function() {
    local function_call=$1
    local test_name=$2
    local expected_result=$3  # "success" или "error"
    
    if [ -z "$expected_result" ]; then
        expected_result="success"
    fi
    
    echo "Тестирование: $test_name"
    result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "$function_call" 2>&1)
    
    if [ "$expected_result" = "success" ]; then
        if [ -z "$(echo "$result" | grep -i "error")" ]; then
            echo -e "${GREEN}+++ УСПЕХ: Функция выполнена (как и ожидалось)${NC}"
        else
            echo -e "${RED}--- ОШИБКА: Функция не выполнена (но должна была)${NC}"
            echo "$result"
        fi
    else
        if [ -n "$(echo "$result" | grep -i "error")" ]; then
            echo -e "${GREEN}+++ УСПЕХ: Функция отклонена (как и ожидалось)${NC}"
        else
            echo -e "${RED}--- ОШИБКА: Функция выполнена (но не должна была)${NC}"
            echo "$result"
        fi
    fi
    echo ""
}

# Функция для получения ID тестовой группы
get_test_group_id() {
    local group_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT group_id FROM app.study_groups WHERE group_id = 1000 LIMIT 1;" 2>&1 | tr -d '[:space:]')
    echo "$group_id"
}

# Функция для получения ID тестового студента
get_test_student_id() {
    local student_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT student_id FROM app.students WHERE student_id = 1000 LIMIT 1;" 2>&1 | tr -d '[:space:]')
    echo "$student_id"
}

# Функция для получения ID тестового преподавателя
get_test_teacher_id() {
    local teacher_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT teacher_id FROM app.teachers WHERE teacher_id = 1000 LIMIT 1;" 2>&1 | tr -d '[:space:]')
    echo "$teacher_id"
}

# Функция для очистки тестовых данных
cleanup_test_data() {
    echo "Очистка тестовых данных..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Сначала очищаем таблицу сопоставления ролей
    DELETE FROM app.role_segments WHERE role_name LIKE 'test_%' OR segment_id = 1000 OR segment_id = 1001;
    
    -- Удаляем в правильном порядке из-за внешних ключей
    DELETE FROM app.student_documents WHERE student_id IN (1000, 1001);
    DELETE FROM app.students WHERE student_id IN (1000, 1001);
    DELETE FROM app.teacher_departments WHERE teacher_id IN (1000, 1001);
    DELETE FROM app.teachers WHERE teacher_id IN (1000, 1001);
    DELETE FROM app.study_groups WHERE group_id IN (1000, 1001);
    DELETE FROM app.faculties WHERE faculty_id IN (1000, 1001);
    DELETE FROM app.educational_institutions WHERE institution_id IN (1000, 1001);
    DELETE FROM ref.segments WHERE segment_id IN (1000, 1001);
    
    DROP TABLE IF EXISTS app.test_table, app.unauthorized_table, ref.unauthorized_ref_table, app.test_table1;
    DROP TABLE IF EXISTS audit.unauthorized_audit_table;
    COMMENT ON SCHEMA app IS 'NULL';
    
    -- Удаляем тестовые роли
    DROP ROLE IF EXISTS test_reader_1000, test_writer_1000, test_reader_1001, test_writer_1001;
EOF
}

# Создаем тестовые роли
create_test_roles

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

# Получаем ID для тестов
TEST_GROUP_ID=$(get_test_group_id)
TEST_STUDENT_ID=$(get_test_student_id)
TEST_TEACHER_ID=$(get_test_teacher_id)

echo "Тестовые ID: группа=$TEST_GROUP_ID, студент=$TEST_STUDENT_ID, преподаватель=$TEST_TEACHER_ID"

# 1. Тестирование роли app_reader с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_reader С СЕГМЕНТАЦИЕЙ ===${NC}"
manage_role "GRANT" "test_reader_1000"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1); SELECT first_name FROM app.students WHERE segment_id = 1000 LIMIT 1;" "test_reader_1000: SELECT в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000, 1); SELECT subject_name FROM ref.subjects LIMIT 1;" "test_reader_1000: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1); INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Тестов', 'test3', 'TEST003', $TEST_GROUP_ID, 1000);" "test_reader_1000: INSERT в схеме app" "error"
check_command "SELECT app.set_session_ctx(1000, 1); CREATE TABLE app.unauthorized_table (id serial);" "test_reader_1000: CREATE TABLE в схеме app" "error"
check_command "SELECT app.set_session_ctx(1000, 1); SELECT first_name FROM app.students WHERE segment_id = 1 LIMIT 1;" "test_reader_1000: SELECT в чужом сегменте" "success"

manage_role "REVOKE" "test_reader_1000"

# 2. Тестирование роли app_writer с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_writer С СЕГМЕНТАЦИЕЙ ===${NC}"
manage_role "GRANT" "test_writer_1000"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1); SELECT COUNT(*) FROM app.students WHERE student_card_number = 'TEST1000';" "test_writer_1000: SELECT в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000, 1); SELECT subject_name FROM ref.subjects LIMIT 1;" "test_writer_1000: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1); CREATE TABLE app.unauthorized_table (id serial);" "test_writer_1000: CREATE TABLE в схеме app" "error"
check_command "SELECT app.set_session_ctx(1000, 1); SELECT first_name FROM app.students WHERE segment_id = 1 LIMIT 1;" "test_writer_1000: SELECT в чужом сегменте" "success"

manage_role "REVOKE" "test_writer_1000"

# 3. Тестирование роли app_owner с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_owner С СЕГМЕНТАЦИЕЙ ===${NC}"
manage_role "GRANT" "test_owner_1000"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1); DELETE FROM app.students WHERE student_card_number = 'TEST1000';" "test_owner_1000: DELETE в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000, 1); CREATE TABLE app.test_table (id serial, name text);" "test_owner_1000: CREATE TABLE в схеме app" "success"
check_command "SELECT app.set_session_ctx(1000, 1); COMMENT ON SCHEMA app IS 'тестовый комм';" "test_owner_1000: COMMENT ON TABLE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1); CREATE TABLE ref.unauthorized_ref_table (id serial);" "test_owner_1000: CREATE TABLE в схеме ref" "error"
check_command "SELECT app.set_session_ctx(1000, 1); DELETE FROM app.students WHERE segment_id = 1;" "test_owner_1000: DELETE в чужом сегменте" "success"

manage_role "REVOKE" "test_owner_1000"

# 4. Тестирование роли auditor
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ auditor ===${NC}"
manage_role "GRANT" "auditor"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "auditor: SELECT в схеме audit" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "auditor: INSERT в схеме audit" "error"
check_command "CREATE TABLE audit.unauthorized_table (id serial);" "auditor: CREATE TABLE в схеме audit" "error"

manage_role "REVOKE" "auditor"

# 5. Тестирование роли ddl_admin (доступ ко всем сегментам)
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ddl_admin (все сегменты) ===${NC}"
manage_role "GRANT" "ddl_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "CREATE TABLE app.test_table1 (id serial, name text);" "ddl_admin: CREATE TABLE в схеме app" "success"
check_command "ALTER TABLE app.test_table ADD COLUMN description text;" "ddl_admin: ALTER TABLE в схеме app" "success"
check_command "SELECT table_name FROM information_schema.tables WHERE table_schema = 'app' LIMIT 1;" "ddl_admin: SELECT метаданных" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Неавторизованный', 'test', 'TESTDDL', 1, 1);" "ddl_admin: INSERT в таблицу" "error"
check_command "SELECT first_name FROM app.students LIMIT 1;" "ddl_admin: SELECT данных из таблиц" "error"

# Очистка тестовых таблиц DDL администратора
sudo docker exec -i postgres psql -U postgres -d education_db -c "DROP TABLE IF EXISTS app.test_table, app.test_table1;" 2>&1

manage_role "REVOKE" "ddl_admin"

# 6. Тестирование роли dml_admin (доступ ко всем сегментам)
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ dml_admin (все сегменты) ===${NC}"
manage_role "GRANT" "dml_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
# Восстанавливаем тестового студента для UPDATE
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id) 
VALUES (1000, 'Тестов1000', 'test1000', 'TEST1000', 1000, 1000)
ON CONFLICT (student_id) DO UPDATE SET last_name = 'Тестов1000';" 2>&1

check_command "UPDATE app.students SET last_name = 'Updated' WHERE student_card_number = 'TEST1000';" "dml_admin: UPDATE в схеме app" "success"
check_command "SELECT first_name FROM app.students LIMIT 1;" "dml_admin: SELECT из students" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "dml_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "dml_admin: INSERT в схеме audit" "error"

manage_role "REVOKE" "dml_admin"

# 7. Тестирование роли security_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ security_admin ===${NC}"
manage_role "GRANT" "security_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT rolname FROM pg_roles LIMIT 5;" "security_admin: SELECT из pg_roles" "success"
check_command "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'app';" "security_admin: SELECT из pg_tables" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "security_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Тестов', 'test4', 'TEST004', 1, 1);" "security_admin: INSERT в схеме app" "error"

manage_role "REVOKE" "security_admin"

# ====================================================================
# ТЕСТИРОВАНИЕ RLS И СЕГМЕНТАЦИИ (8+ КЕЙСОВ)
# ====================================================================

echo -e "${YELLOW}=== ТЕСТИРОВАНИЕ RLS И СЕГМЕНТАЦИИ (8+ КЕЙСОВ) ===${NC}"

# КЕЙС 1: Чтение «чужих» строк (должно быть пусто)
echo -e "${BLUE}=== КЕЙС 1: Чтение «чужих» строк (должно быть пусто) ===${NC}"
manage_role "GRANT" "test_reader_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1001;" "Чтение студентов из чужого сегмента 1001" 0
check_row_count "SELECT * FROM app.teachers WHERE segment_id = 1001;" "Чтение преподавателей из чужого сегмента 1001" 0

manage_role "REVOKE" "test_reader_1000"

# КЕЙС 2: Вставка с неверным segment_id (ошибка)
echo -e "${BLUE}=== КЕЙС 2: Вставка с неверным segment_id (ошибка) ===${NC}"
manage_role "GRANT" "test_writer_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Чужой', 'Студент', 'FOREIGN001', 1000, 1001);" "Вставка студента с segment_id=1001 (чужой сегмент)" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Несуществующий', 'Студент', 'GHOST001', 1000, 999);" "Вставка студента с segment_id=999 (несуществующий)" "error"

manage_role "REVOKE" "test_writer_1000"

# КЕЙС 3: Обновление с неверным segment_id (ошибка)
echo -e "${BLUE}=== КЕЙС 3: Обновление с неверным segment_id (ошибка) ===${NC}"
manage_role "GRANT" "test_writer_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_command "UPDATE app.students SET last_name = 'Взломан' WHERE segment_id = 1001;" "Обновление студентов в сегменте 1001 (чужой)" "error"
check_command "UPDATE app.students SET segment_id = 1001 WHERE student_id = 1000;" "Изменение segment_id на 1001 (чужой)" "error"

manage_role "REVOKE" "test_writer_1000"

# КЕЙС 4: Корректные операции в своём сегменте (чтение)
echo -e "${BLUE}=== КЕЙС 4: Корректные операции в своём сегменте (чтение) ===${NC}"
manage_role "GRANT" "test_reader_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1000;" "Чтение студентов из своего сегмента 1000" 1
check_row_count "SELECT * FROM app.teachers WHERE segment_id = 1000;" "Чтение преподавателей из своего сегмента 1000" 1
check_command "SELECT last_name FROM app.students WHERE segment_id = 1000;" "Проверка данных студентов сегмента 1000" "success"

manage_role "REVOKE" "test_reader_1000"

# КЕЙС 5: Корректные операции в своём сегменте (запись)
echo -e "${BLUE}=== КЕЙС 5: Корректные операции в своём сегменте (запись) ===${NC}"
manage_role "GRANT" "test_writer_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id, email) VALUES ('Новый', 'Студент1000', 'NEW1000', 1000, 1000, 'new1000@test.ru');" "Вставка студента в сегмент 1000" "success"
check_command "UPDATE app.students SET last_name = 'Обновленный' WHERE student_card_number = 'NEW1000';" "Обновление студента в сегменте 1000" "success"
check_command "DELETE FROM app.students WHERE student_card_number = 'NEW1000';" "Удаление студента из сегмента 1000" "success"

manage_role "REVOKE" "test_writer_1000"

# КЕЙС 6: Проверка работы set_session_ctx() - успешная
echo -e "${BLUE}=== КЕЙС 6: Проверка работы set_session_ctx() - успешная ===${NC}"
manage_role "GRANT" "test_reader_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000 (успешно)" "success"
check_command "SELECT * FROM app.get_session_ctx();" "Проверка установленного контекста" "success"
check_row_count "SELECT * FROM app.students;" "Доступ к данным после установки контекста" 1

manage_role "REVOKE" "test_reader_1000"

# КЕЙС 7: Проверка работы set_session_ctx() - ошибка (сегмент не принадлежит роли)
echo -e "${BLUE}=== КЕЙС 7: Проверка работы set_session_ctx() - ошибка (сегмент не принадлежит роли) ===${NC}"
manage_role "GRANT" "test_reader_1000"

check_command "SELECT app.set_session_ctx(1001, 1000);" "Установка контекста для сегмента 1001 (чужой)" "error"
check_command "SELECT app.set_session_ctx(9999, 1000);" "Установка контекста для сегмента 9999 (несуществующий)" "error"

manage_role "REVOKE" "test_reader_1000"

# КЕЙС 8: Перекрестное тестирование разных ролей и сегментов
echo -e "${BLUE}=== КЕЙС 8: Перекрестное тестирование разных ролей и сегментов ===${NC}"

manage_role "GRANT" "test_reader_1001"
check_command "SELECT app.set_session_ctx(1001, 1001);" "Установка контекста для сегмента 1001" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1001;" "Чтение студентов из сегмента 1001" 1
check_row_count "SELECT * FROM app.students WHERE segment_id = 1000;" "Чтение студентов из сегмента 1000 (чужой)" 0
manage_role "REVOKE" "test_reader_1001"

manage_role "GRANT" "test_writer_1001"
check_command "SELECT app.set_session_ctx(1001, 1001);" "Установка контекста для сегмента 1001" "success"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id, email) VALUES ('Новый1001', 'Студент1001', 'NEW1001', 1001, 1001, 'new1001@test.ru');" "Вставка студента в сегмент 1001" "success"
check_command "DELETE FROM app.students WHERE student_card_number = 'NEW1001';" "Очистка тестовых данных 1001" "success"
manage_role "REVOKE" "test_writer_1001"

# КЕЙС 9: Тестирование без установки контекста
echo -e "${BLUE}=== КЕЙС 9: Тестирование без установки контекста ===${NC}"
manage_role "GRANT" "test_reader_1000"

check_row_count "SELECT * FROM app.students;" "Чтение без установки контекста" 0

manage_role "REVOKE" "test_reader_1000"

# КЕЙС 10: Тестирование административных ролей (доступ ко всем сегментам)
echo -e "${BLUE}=== КЕЙС 10: Тестирование административных ролей (доступ ко всем сегментам) ===${NC}"
manage_role "GRANT" "dml_admin"

check_row_count "SELECT * FROM app.students;" "DML_ADMIN: чтение всех студентов" 2
check_row_count "SELECT * FROM app.teachers;" "DML_ADMIN: чтение всех преподавателей" 2

manage_role "REVOKE" "dml_admin"

# КЕЙС 11: Тестирование функций с сегментацией
echo -e "${BLUE}=== КЕЙС 11: Тестирование функций с сегментацией ===${NC}"
manage_role "GRANT" "test_writer_1000"

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для функций" "success"
check_command "SELECT app.add_student_document(1000, 'ИНН'::public.document_type_enum, NULL, 'INN1000', '2024-01-01', 'ИФНС');" "Добавление документа в сегменте 1000" "success"
check_command "SELECT app.add_student_document(1001, 'ИНН'::public.document_type_enum, NULL, 'INN1001', '2024-01-01', 'ИФНС');" "Добавление документа для студента из сегмента 1001" "error"

manage_role "REVOKE" "test_writer_1000"

# КЕЙС 12: Проверка изоляции данных между сегментами
echo -e "${BLUE}=== КЕЙС 12: Проверка изоляции данных между сегментами ===${NC}"

manage_role "GRANT" "test_reader_1000"
check_command "SELECT app.set_session_ctx(1000, 1000);" "Контекст для проверки изоляции" "success"
result_1000=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -t -c "SELECT student_card_number FROM app.students ORDER BY student_id;" 2>&1)
echo "Студенты в сегменте 1000: $result_1000"
manage_role "REVOKE" "test_reader_1000"

manage_role "GRANT" "test_reader_1001"
check_command "SELECT app.set_session_ctx(1001, 1001);" "Контекст для проверки изоляции" "success"
result_1001=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -t -c "SELECT student_card_number FROM app.students ORDER BY student_id;" 2>&1)
echo "Студенты в сегменте 1001: $result_1001"
manage_role "REVOKE" "test_reader_1001"

if [ "$result_1000" != "$result_1001" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Данные изолированы между сегментами${NC}"
else
    echo -e "${RED}--- ОШИБКА: Данные не изолированы${NC}"
fi

echo -e "${YELLOW}=== Тестирование SECURITY DEFINER функций с сегментацией ===${NC}"
echo ""

echo "Выдаем права CONNECT и test_writer_1000 пользователю test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT CONNECT ON DATABASE education_db TO test_connect;" 2>&1
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT test_writer_1000 TO test_connect;" 2>&1

# 1. Тестирование функции enroll_student с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ enroll_student С СЕГМЕНТАЦИЕЙ ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1); SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'novikov_alex_new@student.ru', '+7-900-300-01-01', $TEST_GROUP_ID);" "enroll_student: успешное зачисление в сегмент 1000" "success"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

echo -e "${PURPLE}--- Неудачное выполнение ---${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE test_writer_1000 FROM test_connect;" 2>&1
if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1); SELECT app.enroll_student('Петров', 'Иван', 'Сергеевич', 'petrov_ivan@student.ru', '+7-900-300-01-02', $TEST_GROUP_ID);" "enroll_student: отсутствуют права test_writer_1000" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT test_writer_1000 TO test_connect;" 2>&1
if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1); SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'novikov_alex_new@student.ru', '+7-900-300-01-01', $TEST_GROUP_ID);" "enroll_student: почта уже существует" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

# 2. Тестирование функции register_final_grade с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ register_final_grade С СЕГМЕНТАЦИЕЙ ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
# Создаем нового студента и преподавателя в сегменте 1000 для теста оценок
sudo docker exec -i postgres psql -U postgres -d education_db -c "
-- Создаем тестового преподавателя в сегменте 1000
INSERT INTO app.teachers (teacher_id, last_name, first_name, academic_degree, academic_title, segment_id) 
SELECT 1001, 'ТестовыйПреподаватель1000', 'Оценки1000', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1000
WHERE NOT EXISTS (SELECT 1 FROM app.teachers WHERE teacher_id = 1001);

-- Создаем нового студента в том же сегменте
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
SELECT 1001, 'Оценочный', 'Студент', 'TESTGRADE', 1000, 1000, 'grade_student@test.ru'
WHERE NOT EXISTS (SELECT 1 FROM app.students WHERE student_id = 1001);" 2>&1

GRADE_STUDENT_ID=1001
GRADE_TEACHER_ID=1001

if [ -n "$GRADE_STUDENT_ID" ] && [ -n "$GRADE_TEACHER_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1); SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $GRADE_TEACHER_ID, 1, '4', 1);" "register_final_grade: успешная регистрация оценки в сегменте 1000" "success"
else
    echo "Пропускаем тест register_final_grade - не удалось создать необходимые ID"
fi

echo -e "${PURPLE}--- Неудачное выполнение ---${NC}"
# Тест с разными сегментами
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.teachers (teacher_id, last_name, first_name, academic_degree, academic_title, segment_id) 
SELECT 1002, 'ЧужойПреподаватель', 'ДругойСегмент', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1
WHERE NOT EXISTS (SELECT 1 FROM app.teachers WHERE teacher_id = 1002);" 2>&1

FOREIGN_TEACHER_ID=1002

if [ -n "$GRADE_STUDENT_ID" ] && [ -n "$FOREIGN_TEACHER_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1); SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $FOREIGN_TEACHER_ID, 1, '5', 1);" "register_final_grade: студент и преподаватель в разных сегментах" "error"
fi

# 3. Тестирование функции add_student_document с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ add_student_document С СЕГМЕНТАЦИЕЙ ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
# Создаем нового студента для теста документов
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
SELECT 1003, 'Документный', 'Студент', 'TESTDOC', 1000, 1000, 'doc_student@test.ru'
WHERE NOT EXISTS (SELECT 1 FROM app.students WHERE student_id = 1003);" 2>&1

DOC_STUDENT_ID=1003

if [ -n "$DOC_STUDENT_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1); SELECT app.add_student_document($DOC_STUDENT_ID, 'ИНН'::public.document_type_enum, NULL, '0987654321', '2023-08-20', 'ИФНС России');" "add_student_document: успешное добавление документа в сегменте 1000" "success"
else
    echo "Пропускаем тест add_student_document - не удалось создать DOC_STUDENT_ID"
fi

# Очистка тестовых данных
echo "Очистка тестовых данных..."
sudo docker exec -i postgres psql -U postgres -d education_db << EOF
DELETE FROM app.student_documents WHERE student_id IN (1001, 1003);
DELETE FROM app.final_grades WHERE student_id IN (1001, 1003) OR teacher_id IN (1001, 1002);
DELETE FROM app.students WHERE student_id IN (1001, 1003);
DELETE FROM app.teachers WHERE teacher_id IN (1001, 1002);
EOF

# Забираем права в конце
echo "Забираем права у пользователя test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE test_writer_1000 FROM test_connect;" 2>&1
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE CONNECT ON DATABASE education_db FROM test_connect;" 2>&1

echo -e "${YELLOW}=== Конец тестирования SECURITY DEFINER функций ===${NC}"

# Очистка тестовых данных
cleanup_test_data

# Забираем право CONNECT в конце
echo "Забираем право CONNECT у пользователя test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE CONNECT ON DATABASE education_db FROM test_connect;" 2>&1

echo -e "${YELLOW}=== Конец тестирования привилегий ===${NC}"

echo -e "${YELLOW}=== Тестирование audit.login_log ===${NC}"
check_audit
echo -e "${YELLOW}=== Конец тестирования аудита ===${NC}"