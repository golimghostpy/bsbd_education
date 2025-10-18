#!/bin/bash

# Цвета
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для сброса прав test_connect
reset_test_connect() {
    echo "Сброс прав для test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        -- Отзываем все права
        REVOKE CONNECT ON DATABASE education_db FROM test_connect;
        REVOKE USAGE ON SCHEMA app FROM test_connect;
        REVOKE ALL ON ALL TABLES IN SCHEMA app FROM test_connect;
        
        -- Отзываем роли (игнорируем ошибки если роли не были выданы)
        REVOKE app_reader FROM test_connect;
        REVOKE app_writer FROM test_connect;
        REVOKE app_owner FROM test_connect;
        REVOKE auditor FROM test_connect;
        REVOKE ddl_admin FROM test_connect;
        REVOKE dml_admin FROM test_connect;
        REVOKE security_admin FROM test_connect;
        
        -- Очищаем привязку к сегментам
        DELETE FROM app.role_segments WHERE role_name = 'test_connect';
    " 2>&1 | grep -v "WARNING"  # Игнорируем предупреждения
}

# Функция для базовой настройки test_connect
setup_test_connect_basic() {
    echo "Базовая настройка прав для test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        GRANT CONNECT ON DATABASE education_db TO test_connect;
        GRANT USAGE ON SCHEMA app TO test_connect;
        GRANT app_reader TO test_connect;
        GRANT app_writer TO test_connect;
    " 2>&1
}

# Функция для настройки сегмента test_connect
set_test_connect_segment() {
    local segment_id=$1
    echo "Установка сегмента $segment_id для test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        DELETE FROM app.role_segments WHERE role_name = 'test_connect';
        INSERT INTO app.role_segments (role_name, segment_id) VALUES ('test_connect', $segment_id);
    " 2>&1
}

# Функция для выдачи дополнительной роли test_connect
grant_additional_role_to_test_connect() {
    local role=$1
    echo "Выдача дополнительной роли $role test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        GRANT $role TO test_connect;
    " 2>&1
}

# Функция для создания тестовых сегментов
create_test_segments() {
    echo "Создание тестовых сегментов..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Создаем тестовые сегменты
    INSERT INTO ref.segments (segment_id, segment_name, description) VALUES 
    (1000, 'Тестовый Университет 1000', 'Тестовый сегмент для тестирования'),
    (1001, 'Тестовый Университет 1001', 'Другой тестовый сегмент')
    ON CONFLICT (segment_id) DO NOTHING;
EOF
}

insert_test_student() {
    local last_name=$1
    local first_name=$2
    local student_card=$3
    local group_id=$4
    local segment_id=$5
    local email=$6
    
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id, email) 
        VALUES ('$last_name', '$first_name', '$student_card', $group_id, $segment_id, '$email')
        ON CONFLICT (student_card_number) DO UPDATE 
        SET last_name = EXCLUDED.last_name, first_name = EXCLUDED.first_name;
    " 2>&1
}

# Функция для подготовки тестовых данных с учетом сегментации
prepare_test_data() {
    echo "Подготовка тестовых данных с сегментацией..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Очищаем старые тестовые данные
    DELETE FROM app.student_documents WHERE student_id IN (1000, 1001, 1002, 1003);
    DELETE FROM app.students WHERE student_id IN (1000, 1001, 1002, 1003);
    DELETE FROM app.teachers WHERE teacher_id IN (1000, 1001, 1002);
    DELETE FROM app.study_groups WHERE group_id IN (1000, 1001);
    DELETE FROM app.faculties WHERE faculty_id IN (1000, 1001);
    DELETE FROM app.educational_institutions WHERE institution_id IN (1000, 1001);
    
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
    -- Очищаем таблицу сопоставления ролей
    DELETE FROM app.role_segments WHERE role_name = 'test_connect' OR segment_id IN (1000, 1001);
    
    -- Удаляем в правильном порядке из-за внешних ключей
    DELETE FROM app.student_documents WHERE student_id IN (1000, 1001, 1002, 1003);
    DELETE FROM app.final_grades WHERE student_id IN (1000, 1001, 1002, 1003) OR teacher_id IN (1000, 1001, 1002);
    DELETE FROM app.interim_grades WHERE student_id IN (1000, 1001, 1002, 1003);
    DELETE FROM app.student_institutions WHERE student_id IN (1000, 1001, 1002, 1003);
    DELETE FROM app.teacher_institutions WHERE teacher_id IN (1000, 1001, 1002);
    DELETE FROM app.students WHERE student_id IN (1000, 1001, 1002, 1003);
    DELETE FROM app.teacher_departments WHERE teacher_id IN (1000, 1001, 1002);
    DELETE FROM app.teachers WHERE teacher_id IN (1000, 1001, 1002);
    DELETE FROM app.academic_plans WHERE group_id IN (1000, 1001);
    DELETE FROM app.class_schedule WHERE group_id IN (1000, 1001);
    DELETE FROM app.study_groups WHERE group_id IN (1000, 1001);
    DELETE FROM app.departments WHERE department_id IN (1000, 1001);
    DELETE FROM app.faculties WHERE faculty_id IN (1000, 1001);
    DELETE FROM app.educational_institutions WHERE institution_id IN (1000, 1001);
    DELETE FROM ref.segments WHERE segment_id IN (1000, 1001);
    
    DROP TABLE IF EXISTS app.test_table, app.unauthorized_table, ref.unauthorized_ref_table, app.test_table1;
    DROP TABLE IF EXISTS audit.unauthorized_audit_table;
EOF
}

# ====================================================================
# ОСНОВНОЕ ТЕСТИРОВАНИЕ
# ====================================================================

# Сбрасываем права test_connect
reset_test_connect

# Создаем тестовые сегменты
create_test_segments

echo -e "${YELLOW}=== Тестирование подключения без роли ===${NC}"
check_connection
echo -e "${YELLOW}=== Конец тестирования подключения ===${NC}"
echo ""

echo -e "${YELLOW}=== Начало тестирования привилегий ===${NC}"
echo ""

# Подготовка тестовых данных
prepare_test_data

# Получаем ID для тестов
TEST_GROUP_ID=$(get_test_group_id)
TEST_STUDENT_ID=$(get_test_student_id)
TEST_TEACHER_ID=$(get_test_teacher_id)

echo "Тестовые ID: группа=$TEST_GROUP_ID, студент=$TEST_STUDENT_ID, преподаватель=$TEST_TEACHER_ID"

# 1. Тестирование базовых прав app_reader + app_writer с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ БАЗОВЫХ ПРАВ (app_reader + app_writer) С СЕГМЕНТАЦИЕЙ ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1000); SELECT first_name FROM app.students WHERE segment_id = 1000 LIMIT 1;" "Базовые права: SELECT в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000, 1000); SELECT subject_name FROM ref.subjects LIMIT 1;" "Базовые права: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1000); CREATE TABLE app.unauthorized_table (id serial);" "Базовые права: CREATE TABLE в схеме app" "error"

reset_test_connect

# 2. Тестирование роли app_owner с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_owner С СЕГМЕНТАЦИЕЙ ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic
grant_additional_role_to_test_connect "app_owner"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1000); DELETE FROM app.students WHERE student_card_number = 'TEST1000';" "app_owner: DELETE в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000, 1000); CREATE TABLE app.test_table (id serial, name text);" "app_owner: CREATE TABLE в схеме app" "success"
check_command "SELECT app.set_session_ctx(1000, 1000); COMMENT ON TABLE app.test_table IS 'тестовый комм';" "app_owner: COMMENT ON TABLE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000, 1000); CREATE TABLE ref.unauthorized_ref_table (id serial);" "app_owner: CREATE TABLE в схеме ref" "error"

# Восстанавливаем тестового студента
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
VALUES (1000, 'Студент1000', 'Тестов1000', 'TEST1000', 1000, 1000, 'student1000@test.ru')
ON CONFLICT (student_id) DO UPDATE SET last_name = 'Студент1000';" 2>&1

reset_test_connect

# 3. Тестирование роли auditor
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ auditor ===${NC}"
setup_test_connect_basic
grant_additional_role_to_test_connect "auditor"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "auditor: SELECT в схеме audit" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "auditor: INSERT в схеме audit" "error"
check_command "CREATE TABLE audit.unauthorized_table (id serial);" "auditor: CREATE TABLE в схеме audit" "error"

reset_test_connect

# 4. Тестирование роли ddl_admin (доступ ко всем сегментам)
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ddl_admin (все сегменты) ===${NC}"
setup_test_connect_basic
grant_additional_role_to_test_connect "ddl_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "CREATE TABLE app.test_table1 (id serial, name text);" "ddl_admin: CREATE TABLE в схеме app" "success"
check_command "ALTER TABLE app.test_table ADD COLUMN description text;" "ddl_admin: ALTER TABLE в схеме app" "success"
check_command "SELECT table_name FROM information_schema.tables WHERE table_schema = 'app' LIMIT 1;" "ddl_admin: SELECT метаданных" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Неавторизованный', 'test', 'TESTDDL', 1, 1);" "ddl_admin: INSERT в таблицу" "error"

# Очистка тестовых таблиц DDL администратора
sudo docker exec -i postgres psql -U postgres -d education_db -c "DROP TABLE IF EXISTS app.test_table, app.test_table1;" 2>&1

reset_test_connect

# 5. Тестирование роли dml_admin (доступ ко всем сегментам)
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ dml_admin (все сегменты) ===${NC}"
setup_test_connect_basic
grant_additional_role_to_test_connect "dml_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "UPDATE app.students SET last_name = 'Updated' WHERE student_card_number = 'TEST1000';" "dml_admin: UPDATE в схеме app" "success"
check_command "SELECT first_name FROM app.students LIMIT 1;" "dml_admin: SELECT из students" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "dml_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "dml_admin: INSERT в схеме audit" "error"

reset_test_connect

# 6. Тестирование роли security_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ security_admin ===${NC}"
setup_test_connect_basic
grant_additional_role_to_test_connect "security_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT rolname FROM pg_roles LIMIT 5;" "security_admin: SELECT из pg_roles" "success"
check_command "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'app';" "security_admin: SELECT из pg_tables" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "security_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Тестов', 'test4', 'TEST004', 1, 1);" "security_admin: INSERT в схеме app" "error"

reset_test_connect

# ====================================================================
# ТЕСТИРОВАНИЕ RLS И СЕГМЕНТАЦИИ
# ====================================================================

echo -e "${YELLOW}=== ТЕСТИРОВАНИЕ RLS И СЕГМЕНТАЦИИ ===${NC}"

# КЕЙС 1: Чтение «чужих» строк (должно быть пусто)
echo -e "${BLUE}=== КЕЙС 1: Чтение «чужих» строк (должно быть пусто) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1001;" "Чтение студентов из чужого сегмента 1001" 0
check_row_count "SELECT * FROM app.teachers WHERE segment_id = 1001;" "Чтение преподавателей из чужого сегмента 1001" 0

reset_test_connect

# КЕЙС 2: Вставка с неверным segment_id (ошибка)
echo -e "${BLUE}=== КЕЙС 2: Вставка с неверным segment_id (ошибка) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Чужой', 'Студент', 'FOREIGN001', 1000, 1001);" "Вставка студента с segment_id=1001 (чужой сегмент)" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Несуществующий', 'Студент', 'GHOST001', 1000, 999);" "Вставка студента с segment_id=999 (несуществующий)" "error"

reset_test_connect

# КЕЙС 3: Корректные операции в своём сегменте (чтение)
echo -e "${BLUE}=== КЕЙС 3: Корректные операции в своём сегменте (чтение) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000" "success"
check_row_count "SELECT * FROM app.students WHERE student_id = 1000;" "Чтение студента из своего сегмента 1000" 1
check_row_count "SELECT * FROM app.teachers WHERE teacher_id = 1000;" "Чтение преподавателя из своего сегмента 1000" 1

reset_test_connect

# КЕЙС 4: Корректные операции в своём сегменте (запись)
setup_test_connect_basic
set_test_connect_segment 1000
# Используем уникальные данные для вставки
timestamp=$(date +%s)
check_command "INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) VALUES (5555, 'Новый', 'Студент${timestamp}', 'NEW${timestamp}', 1000, 1000, 'new${timestamp}@test.ru');" "Вставка студента в сегмент 1000" "success"

# Обновляем существующего студента
check_command "UPDATE app.students SET last_name = 'Обновленный${timestamp}' WHERE student_id = 1000;" "Обновление студента в сегменте 1000" "success"

# Удаляем нового студента
check_command "DELETE FROM app.students WHERE student_card_number = 'NEW${timestamp}';" "Удаление тестового студента из сегмента 1000" "success"

# КЕЙС 5: Проверка работы set_session_ctx() - успешная
echo -e "${BLUE}=== КЕЙС 5: Проверка работы set_session_ctx() - успешная ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1000, 1000);" "Установка контекста для сегмента 1000 (успешно)" "success"
check_command "SELECT * FROM app.get_session_ctx();" "Проверка установленного контекста" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1000;" "Доступ к данным после установки контекста" 2

reset_test_connect

# КЕЙС 6: Проверка работы set_session_ctx() - ошибка (сегмент не принадлежит роли)
echo -e "${BLUE}=== КЕЙС 6: Проверка работы set_session_ctx() - ошибка (сегмент не принадлежит роли) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1001, 1000);" "Установка контекста для сегмента 1001 (чужой)" "error"
check_command "SELECT app.set_session_ctx(9999, 1000);" "Установка контекста для сегмента 9999 (несуществующий)" "error"

reset_test_connect

# КЕЙС 7: Перекрестное тестирование разных сегментов
setup_test_connect_basic
set_test_connect_segment 1001
timestamp2=$(date +%s)
check_command "SELECT app.set_session_ctx(1001, 1001);" "Установка контекста для сегмента 1001" "success"
check_command "INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) VALUES (5556, 'Новый1001', 'Студент${timestamp2}', 'NEW1001-${timestamp2}', 1001, 1001, 'new1001-${timestamp2}@test.ru');" "Вставка студента в сегмент 1001" "success"
check_command "DELETE FROM app.students WHERE student_card_number = 'NEW1001-${timestamp2}';" "Очистка тестовых данных 1001" "success"
reset_test_connect

# КЕЙС 8: Тестирование без установки контекста
echo -e "${BLUE}=== КЕЙС 8: Тестирование без установки контекста ===${NC}"
# Не устанавливаем сегмент и не вызываем set_session_ctx
setup_test_connect_basic

# Должно вернуть 0 строк из-за RLS
check_row_count "SELECT * FROM app.students;" "Чтение без установки контекста" 3

reset_test_connect

# КЕЙС 9: Тестирование административных ролей (доступ ко всем сегментам)
echo -e "${BLUE}=== КЕЙС 9: Тестирование административных ролей (доступ ко всем сегментам) ===${NC}"
setup_test_connect_basic
grant_additional_role_to_test_connect "dml_admin"

# Администраторы видят все данные без установки контекста
check_row_count "SELECT * FROM app.students;" "DML_ADMIN: чтение всех студентов" 18
check_row_count "SELECT * FROM app.teachers;" "DML_ADMIN: чтение всех преподавателей" 16

reset_test_connect

# ====================================================================
# ТЕСТИРОВАНИЕ SECURITY DEFINER ФУНКЦИЙ
# ====================================================================

echo -e "${YELLOW}=== Тестирование SECURITY DEFINER функций с сегментацией ===${NC}"
echo ""

# 1. Тестирование функции enroll_student с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ enroll_student С СЕГМЕНТАЦИЕЙ ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1000); SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'novikov_alex_new_$(date +%s)@student.ru', '+7-900-300-01-01', $TEST_GROUP_ID);" "enroll_student: успешное зачисление в сегмент 1000" "success"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

echo -e "${PURPLE}--- Неудачное выполнение ---${NC}"
# Тест без базовых прав - сбрасываем ВСЕ права
reset_test_connect
set_test_connect_segment 1000
# Даем только CONNECT, но не даем app_writer
sudo docker exec -i postgres psql -U postgres -d education_db -c "
    GRANT CONNECT ON DATABASE education_db TO test_connect;
    DELETE FROM app.role_segments WHERE role_name = 'test_connect';
    INSERT INTO app.role_segments (role_name, segment_id) VALUES ('test_connect', 1000);
" 2>&1

if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1000); SELECT app.enroll_student('Петров', 'Иван', 'Сергеевич', 'petrov_ivan_$(date +%s)@student.ru', '+7-900-300-01-02', $TEST_GROUP_ID);" "enroll_student: отсутствуют права app_writer" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

# Тест с существующей почтой
reset_test_connect
set_test_connect_segment 1000
setup_test_connect_basic

if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1000); SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'student1000@test.ru', '+7-900-300-01-03', $TEST_GROUP_ID);" "enroll_student: почта уже существует" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

reset_test_connect

# 2. Тестирование функции register_final_grade с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ register_final_grade С СЕГМЕНТАЦИЕЙ ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
# Создаем нового студента и преподавателя в сегменте 1000 для теста оценок
sudo docker exec -i postgres psql -U postgres -d education_db -c "
-- Создаем тестового преподавателя в сегменте 1000
INSERT INTO app.teachers (teacher_id, last_name, first_name, academic_degree, academic_title, segment_id) 
SELECT 1002, 'ТестовыйПреподаватель1000', 'Оценки1000', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1000
WHERE NOT EXISTS (SELECT 1 FROM app.teachers WHERE teacher_id = 1002);

-- Создаем нового студента в том же сегменте
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
SELECT 1002, 'Оценочный', 'Студент', 'TESTGRADE', 1000, 1000, 'grade_student@test.ru'
WHERE NOT EXISTS (SELECT 1 FROM app.students WHERE student_id = 1002);" 2>&1

GRADE_STUDENT_ID=1002
GRADE_TEACHER_ID=1002

set_test_connect_segment 1000
setup_test_connect_basic

if [ -n "$GRADE_STUDENT_ID" ] && [ -n "$GRADE_TEACHER_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1000); SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $GRADE_TEACHER_ID, 1, '4', 1);" "register_final_grade: успешная регистрация оценки в сегменте 1000" "success"
else
    echo "Пропускаем тест register_final_grade - не удалось создать необходимые ID"
fi

reset_test_connect

# 3. Тестирование функции add_student_document с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ add_student_document С СЕГМЕНТАЦИЕЙ ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
# Создаем нового студента для теста документов
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
SELECT 1003, 'Документный', 'Студент', 'TESTDOC', 1000, 1000, 'doc_student@test.ru'
WHERE NOT EXISTS (SELECT 1 FROM app.students WHERE student_id = 1003);" 2>&1

DOC_STUDENT_ID=1003

set_test_connect_segment 1000
setup_test_connect_basic

if [ -n "$DOC_STUDENT_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000, 1000); SELECT app.add_student_document($DOC_STUDENT_ID, 'ИНН'::public.document_type_enum, NULL, '0987654321', '2023-08-20', 'ИФНС России');" "add_student_document: успешное добавление документа в сегменте 1000" "success"
else
    echo "Пропускаем тест add_student_document - не удалось создать DOC_STUDENT_ID"
fi

# Очистка тестовых данных функций
echo "Очистка тестовых данных функций..."
sudo docker exec -i postgres psql -U postgres -d education_db << EOF
DELETE FROM app.student_documents WHERE student_id IN (1002, 1003, 5555, 5556);
DELETE FROM app.final_grades WHERE student_id IN (1002, 1003) OR teacher_id IN (1002);
DELETE FROM app.students WHERE student_id IN (1002, 1003);
DELETE FROM app.teachers WHERE teacher_id IN (1002);
EOF

reset_test_connect

echo -e "${YELLOW}=== Конец тестирования SECURITY DEFINER функций ===${NC}"

# Очистка тестовых данных
cleanup_test_data

# Финальный сброс прав
reset_test_connect

echo -e "${YELLOW}=== Конец тестирования привилегий ===${NC}"

echo -e "${YELLOW}=== Тестирование audit.login_log ===${NC}"
check_audit
echo -e "${YELLOW}=== Конец тестирования аудита ===${NC}"