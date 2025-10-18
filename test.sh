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

# Функция для подготовки тестовых данных с учетом сегментации
prepare_test_data() {
    echo "Подготовка тестовых данных с сегментацией..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Создаем тестовый сегмент
    INSERT INTO ref.segments (segment_id, segment_name, description) 
    VALUES (1000, 'Тестовый Университет', 'Тестовый сегмент для тестирования') 
    ON CONFLICT (segment_id) DO NOTHING;
    
    -- Создаем тестовое учебное заведение
    INSERT INTO app.educational_institutions (institution_name, short_name, legal_address, segment_id) 
    VALUES ('Тестовый Университет 1000', 'ТУ1000', 'Тестовый адрес 1000', 1000)
    ON CONFLICT (institution_name) DO NOTHING;
    
    -- Создаем тестовый факультет
    INSERT INTO app.faculties (faculty_name, institution_id, segment_id) 
    SELECT 'Тестовый Факультет 1000', institution_id, 1000
    FROM app.educational_institutions 
    WHERE institution_name = 'Тестовый Университет 1000'
    ON CONFLICT (faculty_name, segment_id) DO NOTHING;
    
    -- Создаем тестовую группу
    INSERT INTO app.study_groups (group_name, admission_year, faculty_id, segment_id) 
    SELECT 'TEST-1000', 2024, faculty_id, 1000
    FROM app.faculties 
    WHERE faculty_name = 'Тестовый Факультет 1000'
    ON CONFLICT (group_name, segment_id) DO NOTHING;
    
    -- Создаем тестового преподавателя
    INSERT INTO app.teachers (last_name, first_name, academic_degree, academic_title, segment_id) 
    VALUES ('Тестовый1000', 'Преподаватель1000', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1000)
    ON CONFLICT (last_name, first_name, segment_id) DO NOTHING;
    
    -- Создаем тестового студента
    INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) 
    SELECT 'Тестов1000', 'test1000', 'TEST1000', group_id, 1000
    FROM app.study_groups 
    WHERE group_name = 'TEST-1000'
    ON CONFLICT (student_card_number) DO NOTHING;
EOF
}

# Функция для получения ID тестовой группы
get_test_group_id() {
    local group_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT group_id FROM app.study_groups WHERE group_name = 'TEST-1000' AND segment_id = 1000 LIMIT 1;" 2>&1 | tr -d '[:space:]')
    if [ -z "$group_id" ]; then
        group_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT group_id FROM app.study_groups LIMIT 1;" 2>&1 | tr -d '[:space:]')
    fi
    echo "$group_id"
}

# Функция для получения ID тестового студента
get_test_student_id() {
    local student_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT student_id FROM app.students WHERE student_card_number = 'TEST1000' LIMIT 1;" 2>&1 | tr -d '[:space:]')
    if [ -z "$student_id" ]; then
        student_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT student_id FROM app.students LIMIT 1;" 2>&1 | tr -d '[:space:]')
    fi
    echo "$student_id"
}

# Функция для получения ID тестового преподавателя
get_test_teacher_id() {
    local teacher_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT teacher_id FROM app.teachers WHERE last_name = 'Тестовый1000' AND segment_id = 1000 LIMIT 1;" 2>&1 | tr -d '[:space:]')
    if [ -z "$teacher_id" ]; then
        teacher_id=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT teacher_id FROM app.teachers LIMIT 1;" 2>&1 | tr -d '[:space:]')
    fi
    echo "$teacher_id"
}

# Функция для очистки тестовых данных
cleanup_test_data() {
    echo "Очистка тестовых данных..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Удаляем в правильном порядке из-за внешних ключей
    DELETE FROM app.student_documents WHERE student_id IN (SELECT student_id FROM app.students WHERE student_card_number LIKE 'TEST%');
    DELETE FROM app.final_grades WHERE student_id IN (SELECT student_id FROM app.students WHERE student_card_number LIKE 'TEST%');
    DELETE FROM app.interim_grades WHERE student_id IN (SELECT student_id FROM app.students WHERE student_card_number LIKE 'TEST%');
    DELETE FROM app.students WHERE student_card_number LIKE 'TEST%';
    DELETE FROM app.teacher_departments WHERE teacher_id IN (SELECT teacher_id FROM app.teachers WHERE last_name = 'Тестовый1000');
    DELETE FROM app.teachers WHERE last_name = 'Тестовый1000' AND segment_id = 1000;
    DELETE FROM app.study_groups WHERE group_name = 'TEST-1000';
    DELETE FROM app.faculties WHERE faculty_name = 'Тестовый Факультет 1000';
    DELETE FROM app.educational_institutions WHERE institution_name = 'Тестовый Университет 1000';
    DELETE FROM ref.segments WHERE segment_id = 1000;
    
    DROP TABLE IF EXISTS app.test_table, app.unauthorized_table, ref.unauthorized_ref_table, app.test_table1;
    DROP TABLE IF EXISTS audit.unauthorized_audit_table;
    COMMENT ON SCHEMA app IS 'NULL';
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

# Получаем ID для тестов
TEST_GROUP_ID=$(get_test_group_id)
TEST_STUDENT_ID=$(get_test_student_id)
TEST_TEACHER_ID=$(get_test_teacher_id)

echo "Тестовые ID: группа=$TEST_GROUP_ID, студент=$TEST_STUDENT_ID, преподаватель=$TEST_TEACHER_ID"

# 1. Тестирование роли app_reader
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_reader ===${NC}"
manage_role "GRANT" "app_reader"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT first_name FROM app.students LIMIT 1;" "app_reader: SELECT в схеме app" "success"
check_command "SELECT subject_name FROM ref.subjects LIMIT 1;" "app_reader: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Тестов', 'test3', 'TEST003', 1, 1);" "app_reader: INSERT в схеме app" "error"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "app_reader: CREATE TABLE в схеме app" "error"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "app_reader: SELECT в схеме audit" "error"

manage_role "REVOKE" "app_reader"

# 2. Тестирование роли app_writer  
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_writer ===${NC}"
manage_role "GRANT" "app_writer"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT COUNT(*) FROM app.students WHERE student_card_number = 'TEST1000';" "app_writer: SELECT существующего студента" "success"
check_command "SELECT subject_name FROM ref.subjects LIMIT 1;" "app_writer: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "app_writer: CREATE TABLE в схеме app" "error"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "app_writer: SELECT в схеме audit" "error"

manage_role "REVOKE" "app_writer"

# 3. Тестирование роли app_owner
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_owner ===${NC}"
manage_role "GRANT" "app_owner"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "DELETE FROM app.students WHERE student_card_number = 'TEST1000';" "app_owner: DELETE в схеме app" "success"
check_command "CREATE TABLE app.test_table (id serial, name text);" "app_owner: CREATE TABLE в схеме app" "success"
check_command "COMMENT ON SCHEMA app IS 'тестовый комм';" "app_owner: COMMENT ON TABLE в схеме app" "success"
check_command "SELECT obj_description((SELECT oid FROM pg_namespace WHERE nspname = 'app'));" "app_owner: SELECT COMMENT ON TABLE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE ref.unauthorized_ref_table (id serial);" "app_owner: CREATE TABLE в схеме ref" "error"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "app_owner: SELECT в схеме audit" "error"

manage_role "REVOKE" "app_owner"

# 4. Тестирование роли auditor
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ auditor ===${NC}"
manage_role "GRANT" "auditor"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "auditor: SELECT в схеме audit" "success"

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
if [ -n "$TEST_GROUP_ID" ]; then
    check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Неавторизованный', 'test', 'TESTDDL', $TEST_GROUP_ID, 1000);" "ddl_admin: INSERT в таблицу" "error"
else
    check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Неавторизованный', 'test', 'TESTDDL', 1, 1);" "ddl_admin: INSERT в таблицу" "error"
fi

# Очистка тестовых таблиц DDL администратора
sudo docker exec -i postgres psql -U postgres -d education_db -c "DROP TABLE IF EXISTS app.test_table, app.test_table1;" 2>&1

manage_role "REVOKE" "ddl_admin"

# 6. Тестирование роли dml_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ dml_admin ===${NC}"
manage_role "GRANT" "dml_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
# Восстанавливаем тестового студента для UPDATE
if [ -n "$TEST_GROUP_ID" ]; then
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) 
VALUES ('Тестов1000', 'test1000', 'TEST1000', $TEST_GROUP_ID, 1000)
ON CONFLICT (student_card_number) DO UPDATE SET last_name = 'Тестов1000';" 2>&1
fi

check_command "UPDATE app.students SET last_name = 'Updated' WHERE student_card_number = 'TEST1000';" "dml_admin: UPDATE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "dml_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');" "dml_admin: INSERT в схеме audit" "error"
check_command "SELECT log_id FROM audit.login_log LIMIT 1;" "dml_admin: SELECT в схеме audit (через роль auditor)" "error"

manage_role "REVOKE" "dml_admin"

# 7. Тестирование роли security_admin
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ security_admin ===${NC}"
manage_role "GRANT" "security_admin"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT rolname FROM pg_roles LIMIT 5;" "security_admin: SELECT из pg_roles" "success"
check_command "SET ROLE security_admin; CREATE ROLE test_role_123; DROP ROLE test_role_123;" "security_admin: CREATE ROLE с SET ROLE" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "CREATE TABLE app.unauthorized_table (id serial);" "security_admin: CREATE TABLE в схеме app" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Тестов', 'test4', 'TEST004', 1, 1);" "security_admin: INSERT в схеме app" "error"

manage_role "REVOKE" "security_admin"


echo -e "${YELLOW}=== Тестирование SECURITY DEFINER функций ===${NC}"
echo ""

echo "Выдаем права CONNECT и app_writer пользователю test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT CONNECT ON DATABASE education_db TO test_connect;" 2>&1
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT app_writer TO test_connect;" 2>&1

# 1. Тестирование функции enroll_student
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ enroll_student ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'novikov_alex@student.ru', '+7-900-300-01-01', $TEST_GROUP_ID);" "enroll_student: успешное зачисление" "success"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

echo -e "${PURPLE}--- Неудачное выполнение (без прав) ---${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE app_writer FROM test_connect;" 2>&1
if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.enroll_student('Петров', 'Иван', 'Сергеевич', 'petrov_ivan@student.ru', '+7-900-300-01-02', $TEST_GROUP_ID);" "enroll_student: отсутствуют права app_writer" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT app_writer TO test_connect;" 2>&1
if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'novikov_alex@student.ru', '+7-900-300-01-01', $TEST_GROUP_ID);" "enroll_student: почта уже существует" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

# 2. Тестирование функции register_final_grade
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ register_final_grade ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
# Создаем нового студента и преподавателя в одном сегменте для теста оценок
if [ -n "$TEST_GROUP_ID" ]; then
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
-- Создаем тестового преподавателя в сегменте 1000
INSERT INTO app.teachers (last_name, first_name, academic_degree, academic_title, segment_id) 
VALUES ('ТестовыйПреподаватель1000', 'Оценки1000', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1000)
ON CONFLICT (last_name, first_name, segment_id) DO UPDATE SET last_name = 'ТестовыйПреподаватель1000';

-- Создаем нового студента в том же сегменте
INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id, email) 
VALUES ('Оценочный', 'Студент', 'TESTGRADE', $TEST_GROUP_ID, 1000, 'grade_student@test.ru')
ON CONFLICT (student_card_number) DO UPDATE SET email = 'grade_student@test.ru';" 2>&1

    GRADE_STUDENT_ID=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT student_id FROM app.students WHERE student_card_number = 'TESTGRADE';" 2>&1 | tr -d '[:space:]')
    GRADE_TEACHER_ID=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT teacher_id FROM app.teachers WHERE last_name = 'ТестовыйПреподаватель1000' AND segment_id = 1000 LIMIT 1;" 2>&1 | tr -d '[:space:]')
    
    if [ -n "$GRADE_STUDENT_ID" ] && [ -n "$GRADE_TEACHER_ID" ]; then
        check_function "SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $GRADE_TEACHER_ID, 1, '4', 1);" "register_final_grade: успешная регистрация оценки" "success"
    else
        echo "Пропускаем тест register_final_grade - не удалось получить необходимые ID (студент: $GRADE_STUDENT_ID, преподаватель: $GRADE_TEACHER_ID)"
    fi
else
    echo "Пропускаем тест register_final_grade - TEST_GROUP_ID не найден"
fi

echo -e "${PURPLE}--- Неудачное выполнение (без прав) ---${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE app_writer FROM test_connect;" 2>&1
if [ -n "$GRADE_STUDENT_ID" ] && [ -n "$GRADE_TEACHER_ID" ]; then
    check_function "SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $GRADE_TEACHER_ID, 1, '5', 1);" "register_final_grade: отсутствуют права app_writer" "error"
else
    echo "Пропускаем тест register_final_grade - не удалось получить необходимые ID"
fi
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT app_writer TO test_connect;" 2>&1
if [ -n "$GRADE_STUDENT_ID" ] && [ -n "$GRADE_TEACHER_ID" ]; then
    check_function "SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $GRADE_TEACHER_ID, 1, 'abc', 1);" "register_final_grade: неправильная оценка" "error"
else
    echo "Пропускаем тест register_final_grade - не удалось получить необходимые ID"
fi

# 3. Тестирование функции add_student_document
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ ФУНКЦИИ add_student_document ===${NC}"

echo -e "${CYAN}--- Успешное выполнение ---${NC}"
# Создаем нового студента для теста документов
if [ -n "$TEST_GROUP_ID" ]; then
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id, email) 
VALUES ('Документный', 'Студент', 'TESTDOC', $TEST_GROUP_ID, 1000, 'doc_student@test.ru')
ON CONFLICT (student_card_number) DO UPDATE SET email = 'doc_student@test.ru';" 2>&1

    DOC_STUDENT_ID=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT student_id FROM app.students WHERE student_card_number = 'TESTDOC';" 2>&1 | tr -d '[:space:]')
    
    if [ -n "$DOC_STUDENT_ID" ]; then
        check_function "SELECT app.add_student_document($DOC_STUDENT_ID, 'ИНН'::public.document_type_enum, NULL, '0987654321', '2023-08-20', 'ИФНС России');" "add_student_document: успешное добавление документа" "success"
    else
        echo "Пропускаем тест add_student_document - не удалось получить DOC_STUDENT_ID"
    fi
else
    echo "Пропускаем тест add_student_document - TEST_GROUP_ID не найден"
fi

echo -e "${PURPLE}--- Неудачное выполнение (без прав) ---${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE app_writer FROM test_connect;" 2>&1
if [ -n "$DOC_STUDENT_ID" ]; then
    check_function "SELECT app.add_student_document($DOC_STUDENT_ID, 'СНИЛС'::public.document_type_enum, NULL, '098-765-432-02', '2023-08-20', 'ПФР России');" "add_student_document: отсутствуют права app_writer" "error"
else
    echo "Пропускаем тест add_student_document - не удалось получить DOC_STUDENT_ID"
fi
sudo docker exec -i postgres psql -U postgres -d education_db -c "GRANT app_writer TO test_connect;" 2>&1
if [ -n "$DOC_STUDENT_ID" ]; then
    check_function "SELECT app.add_student_document($DOC_STUDENT_ID, 'ИНН'::public.document_type_enum, NULL, '0987654321', '2023-08-20', 'ИФНС России');" "add_student_document: такой тип документа у студента уже есть" "error"
else
    echo "Пропускаем тест add_student_document - не удалось получить DOC_STUDENT_ID"
fi

# Тестирование производительности CHECK vs TRIGGER
echo -e "${YELLOW}=== ТЕСТИРОВАНИЕ CHECK vs TRIGGER ДЛЯ РАСПИСАНИЯ ЗАНЯТИЙ (10k записей) ===${NC}"
echo ""

# подготовительный этап
echo -e "${BLUE}=== ПОДГОТОВКА ===${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "
    DROP TRIGGER IF EXISTS trg_class_time_check ON app.class_schedule;
    ALTER TABLE app.class_schedule DROP CONSTRAINT IF EXISTS chk_class_time;
" 2>&1

# ТЕСТ ТРИГГЕРА
echo -e "${BLUE}=== ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ TRIGGER ===${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "
    CREATE OR REPLACE FUNCTION app.trg_check_class_time()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS \$\$
    BEGIN
        IF NEW.end_time <= NEW.start_time THEN
            RAISE EXCEPTION 'TRIGGER_ERROR: Время окончания занятия (%) должно быть позже времени начала (%)', 
                NEW.end_time, NEW.start_time;
        END IF;
        RETURN NEW;
    END;
    \$\$;

    CREATE TRIGGER trg_class_time_check
        BEFORE INSERT OR UPDATE ON app.class_schedule
        FOR EACH ROW
        EXECUTE FUNCTION app.trg_check_class_time();

    DO \$\$
    DECLARE
        start_time TIMESTAMP;
        end_time INTERVAL;
        i INTEGER;
        success_count INTEGER := 0;
        error_count INTEGER := 0;
    BEGIN
        start_time := clock_timestamp();
        
        FOR i IN 1..10000 LOOP
            BEGIN
                INSERT INTO app.class_schedule (
                    group_id, subject_id, teacher_id, week_number, 
                    day_of_week, start_time, end_time, classroom, 
                    building_number, lesson_type, segment_id
                ) VALUES (
                    1, 1, 1, 1,
                    'Понедельник'::public.day_of_week_enum,
                    '08:00'::time,
                    '09:30'::time,
                    '101',
                    '1',
                    'Лекция'::public.lesson_type_enum,
                    1
                );
                success_count := success_count + 1;
            EXCEPTION WHEN OTHERS THEN
                error_count := error_count + 1;
            END;
        END LOOP;
        
        end_time := clock_timestamp() - start_time;
        
        RAISE NOTICE '=== РЕЗУЛЬТАТЫ TRIGGER ===';
        RAISE NOTICE 'Успешных вставок: %', success_count;
        RAISE NOTICE 'Ошибок: %', error_count;
        RAISE NOTICE 'Время выполнения: %', end_time;
        
        DELETE FROM app.class_schedule WHERE classroom = '101';
    END \$\$;

    DROP TRIGGER trg_class_time_check ON app.class_schedule;
    DROP FUNCTION app.trg_check_class_time();
" 2>&1

# ТЕСТ CHECK ОГРАНИЧЕНИЯ
echo -e "${BLUE}=== ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ CHECK ОГРАНИЧЕНИЯ ===${NC}"
sudo docker exec -i postgres psql -U postgres -d education_db -c "
    ALTER TABLE app.class_schedule 
    ADD CONSTRAINT chk_class_time 
    CHECK (end_time > start_time);

    DO \$\$
    DECLARE
        start_time TIMESTAMP;
        end_time INTERVAL;
        i INTEGER;
        success_count INTEGER := 0;
        error_count INTEGER := 0;
    BEGIN
        start_time := clock_timestamp();
        
        FOR i IN 1..10000 LOOP
            BEGIN
                INSERT INTO app.class_schedule (
                    group_id, subject_id, teacher_id, week_number, 
                    day_of_week, start_time, end_time, classroom, 
                    building_number, lesson_type, segment_id
                ) VALUES (
                    1, 1, 1, 1,
                    'Понедельник'::public.day_of_week_enum,
                    '08:00'::time,
                    '09:30'::time,
                    '101',
                    '1',
                    'Лекция'::public.lesson_type_enum,
                    1
                );
                success_count := success_count + 1;
            EXCEPTION WHEN check_violation THEN
                error_count := error_count + 1;
            END;
        END LOOP;
        
        end_time := clock_timestamp() - start_time;
        
        RAISE NOTICE '=== РЕЗУЛЬТАТЫ CHECK ===';
        RAISE NOTICE 'Успешных вставок: %', success_count;
        RAISE NOTICE 'Ошибок: %', error_count;
        RAISE NOTICE 'Время выполнения: %', end_time;
        
        DELETE FROM app.class_schedule WHERE classroom = '101';
    END \$\$;

    ALTER TABLE app.class_schedule DROP CONSTRAINT chk_class_time;
" 2>&1

# Восстанавливаем CHECK ограничение
sudo docker exec -i postgres psql -U postgres -d education_db -c "
    ALTER TABLE app.class_schedule 
    ADD CONSTRAINT chk_class_time 
    CHECK (end_time > start_time);" 2>&1

echo -e "${GREEN}=== ТЕСТИРОВАНИЕ CHECK vs TRIGGER ДЛЯ РАСПИСАНИЯ ЗАНЯТИЙ ЗАВЕРШЕНО ===${NC}"
echo ""

# Очистка тестовых данных
echo "Очистка тестовых данных..."
sudo docker exec -i postgres psql -U postgres -d education_db << EOF
DELETE FROM app.students WHERE email IN ('novikov_alex@student.ru', 'grade_student@test.ru', 'doc_student@test.ru');
DELETE FROM app.final_grades WHERE student_id IN (SELECT student_id FROM app.students WHERE email IN ('grade_student@test.ru', 'doc_student@test.ru'));
DELETE FROM app.student_documents WHERE document_number = '0987654321';
EOF

# Забираем права в конце
echo "Забираем права у пользователя test_connect"
sudo docker exec -i postgres psql -U postgres -d education_db -c "REVOKE app_writer FROM test_connect;" 2>&1
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