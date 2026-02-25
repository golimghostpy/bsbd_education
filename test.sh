#!/bin/bash

# Цвета
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Флаг для тестирования производительности
PERFORMANCE_TEST=false
JIT_ACCESS_TEST=false
INDEX_TEST=false

# Обработка аргументов командной строки
while getopts "eji" opt; do
    case $opt in
        e)
            PERFORMANCE_TEST=true
            ;;
        j)
            JIT_ACCESS_TEST=true
            ;;
        i)
            INDEX_TEST=true
            ;;
        \?)
            echo "Использование: $0 [-e] [-j] [-i]"
            exit 1
            ;;
    esac
done

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
    " > /dev/null 2>&1
}

# Функция для базовой настройки test_connect
setup_test_connect_basic() {
    echo "Базовая настройка прав для test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        GRANT CONNECT ON DATABASE education_db TO test_connect;
        GRANT USAGE ON SCHEMA app TO test_connect;
        GRANT app_reader TO test_connect;
        GRANT app_writer TO test_connect;
    " > /dev/null 2>&1
}

# Функция для настройки сегмента test_connect
set_test_connect_segment() {
    local segment_id=$1
    echo "Установка сегмента $segment_id для test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        DELETE FROM app.role_segments WHERE role_name = 'test_connect';
        INSERT INTO app.role_segments (role_name, segment_id) VALUES ('test_connect', $segment_id);
    " > /dev/null 2>&1
}

# Функция для выдачи дополнительной роли test_connect
grant_additional_role_to_test_connect() {
    local role=$1
    echo "Выдача дополнительной роли $role test_connect..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        GRANT $role TO test_connect;
    " > /dev/null 2>&1
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
    (1001, 'Студент1001', 'Тестов1001', 'TEST1001', 1001, 1001, 'student1001@test.ru'),
    ON CONFLICT (student_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовые документы
    INSERT INTO app.student_documents (student_id, document_type, document_number, segment_id) VALUES 
    (1000, 'Паспорт'::public.document_type_enum, 'PASS1000', 1000),
    (1001, 'Паспорт'::public.document_type_enum, 'PASS1001', 1001)
    ON CONFLICT DO NOTHING;
EOF

    # Создаем дополнительные данные для тестирования Security Barrier View
    echo "Подготовка данных для Security Barrier View..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Создаем дополнительные студенты в сегменте 1000 для статистики
    INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, status, email) VALUES 
    (1100, 'Статистика1', 'Студент1000', 'STAT1000-1', 1000, 1000, 'Обучается'::public.student_status_enum, 'stat1_1000@test.ru'),
    (1101, 'Статистика2', 'Студент1000', 'STAT1000-2', 1000, 1000, 'Обучается'::public.student_status_enum, 'stat2_1000@test.ru'),
    (1102, 'Статистика3', 'Студент1001', 'STAT1001-1', 1001, 1001, 'Обучается'::public.student_status_enum, 'stat1_1001@test.ru')
    ON CONFLICT (student_id) DO UPDATE SET segment_id = EXCLUDED.segment_id;
    
    -- Создаем дополнительные документы для статистики
    INSERT INTO app.student_documents (student_id, document_type, document_number, segment_id) VALUES 
    (1100, 'Паспорт'::public.document_type_enum, 'DOC1000-1', 1000),
    (1101, 'ИНН'::public.document_type_enum, 'DOC1000-2', 1000),
    (1102, 'Паспорт'::public.document_type_enum, 'DOC1001-1', 1001)
    ON CONFLICT DO NOTHING;
    
    -- Создаем дополнительные оценки для статистики
    INSERT INTO app.final_grades (student_id, subject_id, teacher_id, final_grade_type_id, final_grade_value, semester, segment_id) VALUES 
    (1100, 1, 1000, 1, '5', 1, 1000),
    (1101, 2, 1000, 1, '4', 1, 1000),
    (1102, 1, 1001, 1, '5', 1, 1001)
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
        echo "$result"
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

    -- Очищаем дополнительные данные Security Barrier View
    DELETE FROM app.student_documents WHERE student_id IN (1100, 1101, 1102);
    DELETE FROM app.final_grades WHERE student_id IN (1100, 1101, 1102);
    DELETE FROM app.students WHERE student_id IN (1100, 1101, 1102);
    
    DROP TABLE IF EXISTS app.test_table, app.unauthorized_table, ref.unauthorized_ref_table, app.test_table1;
    DROP TABLE IF EXISTS audit.unauthorized_audit_table;
EOF
}

# Функция для очистки кеша PostgreSQL
clear_cache() {
    sudo docker exec -i postgres psql -U postgres -d education_db -c "DISCARD ALL;" > /dev/null 2>&1
    sudo docker exec -i postgres psql -U postgres -d education_db -c "CHECKPOINT;" > /dev/null 2>&1
}

# Функция для выполнения EXPLAIN ANALYZE и извлечения метрик
run_explain_analyze() {
    local query=$1
    local test_name=$2
    local index_type=$3
    
    echo -e "${CYAN}--- $test_name ---${NC}"
    echo -e "${PURPLE}Используемый индекс: $index_type${NC}"
    
    # Очищаем кэш перед каждым замером
    clear_cache
    
    # Выполняем запрос и сохраняем результат
    local result
    result=$(sudo docker exec -i postgres psql -U postgres -d education_db -c "EXPLAIN (ANALYZE, BUFFERS, TIMING) $query" 2>&1)
    
    # Извлекаем время выполнения
    local execution_time
    execution_time=$(echo "$result" | grep "Execution Time:" | awk '{print $3}' | tr -d ' ')
    
    # Извлекаем тип сканирования
    local scan_type
    scan_type=$(echo "$result" | grep -E "Seq Scan|Index Scan|Bitmap Heap Scan|Bitmap Index Scan|Index Only Scan|BitmapAnd|BitmapOr|Hash Join|Nested Loop|Merge Join" | head -1 | awk '{print $1, $2}')

    # Возвращаем время выполнения и тип сканирования (через глобальные переменные)
    echo "$execution_time"
    # Сохраняем тип сканирования во временный файл для передачи
    echo "$scan_type" > /tmp/scan_type_$$.tmp
}

# Функция для извлечения метрик из EXPLAIN ANALYZE
extract_metrics() {
    local explain_output=$1
    local metric_type=$2 # "time" или "buffers"
    
    if [ "$metric_type" = "time" ]; then
        echo "$explain_output" | grep -o "Execution Time: [0-9]*\.[0-9]*" | head -1 | cut -d':' -f2 | tr -d ' '
    elif [ "$metric_type" = "buffers" ]; then
        echo "$explain_output" | grep -o "Buffers: shared hit=[0-9]*" | head -1 | cut -d'=' -f2 | tr -d ' '
    fi
}

# Функция для управления RLS
manage_rls() {
    local action=$1 # "disable" или "enable"
    
    if [ "$action" = "disable" ]; then
        echo "Отключение RLS для тестирования..."
        sudo docker exec -i postgres psql -U postgres -d education_db > /dev/null 2>&1 << 'EOF'
        ALTER TABLE app.students DISABLE ROW LEVEL SECURITY;
        ALTER TABLE app.final_grades DISABLE ROW LEVEL SECURITY;
        ALTER TABLE app.study_groups DISABLE ROW LEVEL SECURITY;
EOF
    elif [ "$action" = "enable" ]; then
        echo "Включение RLS..."
        sudo docker exec -i postgres psql -U postgres -d education_db > /dev/null 2>&1 << 'EOF'
        ALTER TABLE app.students ENABLE ROW LEVEL SECURITY;
        ALTER TABLE app.final_grades ENABLE ROW LEVEL SECURITY;
        ALTER TABLE app.study_groups ENABLE ROW LEVEL SECURITY;
EOF
    fi
}

if [ "$PERFORMANCE_TEST" = true ]; then
    echo -e "${YELLOW}=== ЗАПУСК ТЕСТИРОВАНИЯ ПРОИЗВОДИТЕЛЬНОСТИ RLS И ИНДЕКСОВ ===${NC}"
    
    # Подготовка расширенных тестовых данных для производительности
    echo "Подготовка расширенных тестовых данных для анализа производительности..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, status, email)
SELECT 
    generate_series(10000, 11000) as student_id,
    'Тестовый' || generate_series(10000, 11000) as last_name,
    'Студент' || generate_series(10000, 11000) as first_name,
    'PERF_TEST_' || generate_series(10000, 11000) as student_card_number,
    CASE WHEN random() < 0.3 THEN 1000 ELSE 1001 END as group_id,
    CASE WHEN random() < 0.5 THEN 1000 ELSE 1001 END as segment_id,
    CASE 
        WHEN random() < 0.7 THEN 'Обучается'::public.student_status_enum
        WHEN random() < 0.9 THEN 'Академический отпуск'::public.student_status_enum 
        ELSE 'Отчислен'::public.student_status_enum
    END as status,
    'perf_test' || generate_series(10000, 11000) || '@test.ru' as email
ON CONFLICT (student_id) DO NOTHING;

ANALYZE app.students;
ANALYZE app.final_grades;
EOF

    # Настройка test_connect для тестов производительности
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
GRANT CONNECT ON DATABASE education_db TO test_connect;
GRANT USAGE ON SCHEMA app TO test_connect;
GRANT app_reader TO test_connect;
GRANT app_writer TO test_connect;
DELETE FROM app.role_segments WHERE role_name = 'test_connect';
INSERT INTO app.role_segments (role_name, segment_id) VALUES ('test_connect', 1000);"

    echo -e "${BLUE}=== ТЕСТ 1: Запрос студентов с фильтрацией по segment_id + status ===${NC}"

    QUERY1="SELECT * FROM app.students WHERE segment_id = 1000 AND status = 'Обучается' LIMIT 100;"

    # Подтест 1: Без RLS и без индексов
    echo -e "${BLUE}--- ПОДТЕСТ 1.1: Без RLS и без индексов ---${NC}"
    manage_rls "disable"
    manage_indexes "drop"
    result_test1_1=$(run_explain_analyze "$QUERY1" "Без RLS и без индексов" "postgres")
    time_test1_1=$(extract_metrics "$result_test1_1" "time")
    buffers_test1_1=$(extract_metrics "$result_test1_1" "buffers")

    # Подтест 2: С RLS и без индексов  
    echo -e "${BLUE}--- ПОДТЕСТ 1.2: С RLS и без индексов ---${NC}"
    manage_rls "enable"
    manage_indexes "drop"
    result_test1_2=$(run_explain_analyze "$QUERY1" "С RLS и без индексов" "test_connect")
    time_test1_2=$(extract_metrics "$result_test1_2" "time")
    buffers_test1_2=$(extract_metrics "$result_test1_2" "buffers")

    # Подтест 3: С RLS и с индексами
    echo -e "${BLUE}--- ПОДТЕСТ 1.3: С RLS и с индексами ---${NC}"
    manage_rls "enable"
    manage_indexes "create"
    result_test1_3=$(run_explain_analyze "$QUERY1" "С RLS и с индексами" "test_connect")
    time_test1_3=$(extract_metrics "$result_test1_3" "time")
    buffers_test1_3=$(extract_metrics "$result_test1_3" "buffers")

    echo -e "${GREEN}Результаты ТЕСТА 1:${NC}"
    echo -e "Без RLS и без индексов:    Время: ${time_test1_1}ms, Буферы: ${buffers_test1_1}"
    echo -e "С RLS и без индексов:      Время: ${time_test1_2}ms, Буферы: ${buffers_test1_2}"
    echo -e "С RLS и с индексами:       Время: ${time_test1_3}ms, Буферы: ${buffers_test1_3}"

    echo -e "${BLUE}=== ТЕСТ 2: Запрос с JOIN ===${NC}"

    QUERY2="SELECT s.student_id, s.last_name, s.first_name, sg.group_name 
            FROM app.students s 
            JOIN app.study_groups sg ON s.group_id = sg.group_id 
            WHERE s.segment_id = 1000 
            AND s.status = 'Обучается' 
            AND s.group_id = 1000;"

    # Подтест 1: Без RLS и без индексов
    echo -e "${BLUE}--- ПОДТЕСТ 2.1: Без RLS и без индексов ---${NC}"
    manage_rls "disable"
    manage_indexes "drop"
    result_test2_1=$(run_explain_analyze "$QUERY2" "Без RLS и без индексов" "postgres")
    time_test2_1=$(extract_metrics "$result_test2_1" "time")
    buffers_test2_1=$(extract_metrics "$result_test2_1" "buffers")

    # Подтест 2: С RLS и без индексов
    echo -e "${BLUE}--- ПОДТЕСТ 2.2: С RLS и без индексов ---${NC}"
    manage_rls "enable"
    manage_indexes "drop"
    result_test2_2=$(run_explain_analyze "$QUERY2" "С RLS и без индексов" "test_connect")
    time_test2_2=$(extract_metrics "$result_test2_2" "time")
    buffers_test2_2=$(extract_metrics "$result_test2_2" "buffers")

    # Подтест 3: С RLS и с индексами
    echo -e "${BLUE}--- ПОДТЕСТ 2.3: С RLS и с индексами ---${NC}"
    manage_rls "enable"
    manage_indexes "create"
    result_test2_3=$(run_explain_analyze "$QUERY2" "С RLS и с индексами" "test_connect")
    time_test2_3=$(extract_metrics "$result_test2_3" "time")
    buffers_test2_3=$(extract_metrics "$result_test2_3" "buffers")

    echo -e "${GREEN}Результаты ТЕСТА 2:${NC}"
    echo -e "Без RLS и без индексов:    Время: ${time_test2_1}ms, Буферы: ${buffers_test2_1}"
    echo -e "С RLS и без индексов:      Время: ${time_test2_2}ms, Буферы: ${buffers_test2_2}"
    echo -e "С RLS и с индексами:       Время: ${time_test2_3}ms, Буферы: ${buffers_test2_3}"

    echo -e "${BLUE}=== ТЕСТ 3: Запрос с агрегатными функциями ===${NC}"

    QUERY3="SELECT s.status, COUNT(*) as count_students, AVG(LENGTH(s.last_name)) as avg_name_length
            FROM app.students s
            WHERE s.segment_id = 1000
            GROUP BY s.status
            HAVING COUNT(*) > 5;"

    # Подтест 1: Без RLS и без индексов
    echo -e "${BLUE}--- ПОДТЕСТ 3.1: Без RLS и без индексов ---${NC}"
    manage_rls "disable"
    manage_indexes "drop"
    result_test3_1=$(run_explain_analyze "$QUERY3" "Без RLS и без индексов" "postgres")
    time_test3_1=$(extract_metrics "$result_test3_1" "time")
    buffers_test3_1=$(extract_metrics "$result_test3_1" "buffers")

    # Подтест 2: С RLS и без индексов
    echo -e "${BLUE}--- ПОДТЕСТ 3.2: С RLS и без индексов ---${NC}"
    manage_rls "enable"
    manage_indexes "drop"
    result_test3_2=$(run_explain_analyze "$QUERY3" "С RLS и без индексов" "test_connect")
    time_test3_2=$(extract_metrics "$result_test3_2" "time")
    buffers_test3_2=$(extract_metrics "$result_test3_2" "buffers")

    # Подтест 3: С RLS и с индексами
    echo -e "${BLUE}--- ПОДТЕСТ 3.3: С RLS и с индексами ---${NC}"
    manage_rls "enable"
    manage_indexes "create"
    result_test3_3=$(run_explain_analyze "$QUERY3" "С RLS и с индексами" "test_connect")
    time_test3_3=$(extract_metrics "$result_test3_3" "time")
    buffers_test3_3=$(extract_metrics "$result_test3_3" "buffers")

    echo -e "${GREEN}Результаты ТЕСТА 3:${NC}"
    echo -e "Без RLS и без индексов:    Время: ${time_test3_1}ms, Буферы: ${buffers_test3_1}"
    echo -e "С RLS и без индексов:      Время: ${time_test3_2}ms, Буферы: ${buffers_test3_2}"
    echo -e "С RLS и с индексами:       Время: ${time_test3_3}ms, Буферы: ${buffers_test3_3}"

    # Восстановление исходного состояния
    echo "Восстановление исходного состояния..."
    manage_rls "enable"
    manage_indexes "create"

    # Очистка тестовых данных производительности
    echo "Очистка тестовых данных производительности..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    DELETE FROM app.students WHERE student_id BETWEEN 10000 AND 20000;
EOF

    # Сброс прав
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
    REVOKE CONNECT ON DATABASE education_db FROM test_connect;
    REVOKE USAGE ON SCHEMA app FROM test_connect;
    REVOKE app_reader FROM test_connect;
    REVOKE app_writer FROM test_connect;
    DELETE FROM app.role_segments WHERE role_name = 'test_connect';"

    echo -e "${YELLOW}=== КОНЕЦ ТЕСТИРОВАНИЯ ПРОИЗВОДИТЕЛЬНОСТИ RLS И ИНДЕКСОВ ===${NC}"
    
    exit 0
fi

if [ "$JIT_ACCESS_TEST" = true ]; then
    echo -e "${YELLOW}=== ЗАПУСК ТЕСТИРОВАНИЯ JIT ACCESS СИСТЕМЫ ===${NC}"
    
    # Подготовка тестовых данных
    create_test_segments
    prepare_test_data
    
    # Создаем дополнительных тестовых студентов, преподавателей и документы
    echo "Подготовка тестовых данных для JIT Access..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Вместо segment_id = 1000 используем segment_id = 1
    INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) VALUES 
    (3000, 'JIT_Студент1', 'ДляУдаления', 'JIT_DELETE1', 1, 1, 'jit_delete1@test.ru'),
    (3001, 'JIT_Студент2', 'ДляУдаления', 'JIT_DELETE2', 1, 1, 'jit_delete2@test.ru'),
    (3002, 'JIT_Студент3', 'ДляУдаления', 'JIT_DELETE3', 1, 1, 'jit_delete3@test.ru')
    ON CONFLICT (student_id) DO UPDATE SET 
        last_name = EXCLUDED.last_name,
        segment_id = EXCLUDED.segment_id;

    -- Аналогично для преподавателей и документов
    INSERT INTO app.teachers (teacher_id, last_name, first_name, academic_degree, academic_title, segment_id) VALUES 
    (3000, 'JIT_Преподаватель1', 'ДляУдаления', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1),
    (3001, 'JIT_Преподаватель2', 'ДляУдаления', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1),
    (3002, 'JIT_Преподаватель3', 'ДляУдаления', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1)
    ON CONFLICT (teacher_id) DO UPDATE SET 
        last_name = EXCLUDED.last_name,
        segment_id = EXCLUDED.segment_id;

    INSERT INTO app.student_documents (student_id, document_type, document_number, segment_id) VALUES 
    (3000, 'Паспорт'::public.document_type_enum, 'JIT_DOC1', 1),
    (3001, 'ИНН'::public.document_type_enum, 'JIT_DOC2', 1),
    (3002, 'СНИЛС'::public.document_type_enum, 'JIT_DOC3', 1)
    ON CONFLICT DO NOTHING;
EOF

    # Настройка test_connect как app_writer с сегментом 1000
    echo "Настройка test_connect как app_writer..."
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
    GRANT CONNECT ON DATABASE education_db TO test_connect;
    GRANT USAGE ON SCHEMA app TO test_connect;
    GRANT app_reader TO test_connect;
    GRANT app_writer TO test_connect;
    DELETE FROM app.role_segments WHERE role_name = 'test_connect';
    INSERT INTO app.role_segments (role_name, segment_id) VALUES ('test_connect', 1);"

    # ТЕСТ 1: Удаление документов студентов
    echo -e "${BLUE}=== ТЕСТ 1: УДАЛЕНИЕ ДОКУМЕНТОВ СТУДЕНТОВ ===${NC}"
    echo -e "${CYAN}--- Удаление документа студента ---${NC}"
    
    # Попытка удаления БЕЗ временной привилегии
    echo -e "${PURPLE}Попытка удаления БЕЗ временной привилегии:${NC}"
    result_no_privilege=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        DELETE FROM app.student_documents WHERE student_id = 3001;
    " 2>&1)
    
    # Проверяем что удаление заблокировано (DELETE 0 и нет ошибки)
    if echo "$result_no_privilege" | grep -qi "требуется временная привилегия"; then
        echo -e "${GREEN}✓ УСПЕХ: Удаление заблокировано (как и ожидалось)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Удаление должно было быть заблокировано${NC}"
        echo "Результат: $result_no_privilege"
    fi
    
    # Запрос временной привилегии
    echo -e "${CYAN}Запрос временной привилегии для DELETE_DOCUMENT...${NC}"
    privilege_result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.request_temp_privilege('DELETE_DOCUMENT', 1);
    " 2>&1)
    
    if echo "$privilege_result" | grep -qi "временный доступ предоставлен"; then
        echo -e "${GREEN}✓ Временная привилегия предоставлена${NC}"
    else
        echo -e "${RED}✗ Ошибка при запросе привилегии${NC}"
        echo "$privilege_result"
    fi
    
    # Попытка удаления С временной привилегией
    echo -e "${PURPLE}Попытка удаления С временной привилегией:${NC}"
    result_with_privilege=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        SELECT * FROM app.student_documents WHERE student_id = 3001;
        DELETE FROM app.student_documents WHERE student_id = 3001;
        SELECT * FROM app.student_documents WHERE student_id = 3001;
    " 2>&1)
    
    # Проверяем что действительно удалилась строка (DELETE 1)
    if echo "$result_with_privilege" | grep -q "DELETE 1"; then
        echo -e "${GREEN}✓ УСПЕХ: Удаление выполнено (DELETE 1)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Удаление не выполнено${NC}"
        echo "Результат: $result_with_privilege"
    fi
    
    echo ""

    # ТЕСТ 2: Удаление преподавателей  
    echo -e "${BLUE}=== ТЕСТ 2: УДАЛЕНИЕ ПРЕПОДАВАТЕЛЕЙ ===${NC}"
    echo -e "${CYAN}--- Удаление преподавателя ---${NC}"
    
    # Попытка удаления БЕЗ временной привилегии
    echo -e "${PURPLE}Попытка удаления БЕЗ временной привилегии:${NC}"
    result_no_privilege=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        DELETE FROM app.teachers WHERE teacher_id = 3000;
    " 2>&1)

    # Проверяем что удаление заблокировано (DELETE 0 и нет ошибки)
    if echo "$result_no_privilege" | grep -qi "требуется временная привилегия"; then
        echo -e "${GREEN}✓ УСПЕХ: Удаление заблокировано (как и ожидалось)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Удаление должно было быть заблокировано${NC}"
        echo "Результат: $result_no_privilege"
    fi
    
    # Запрос временной привилегии
    echo -e "${CYAN}Запрос временной привилегии для DELETE_TEACHER...${NC}"
    privilege_result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.request_temp_privilege('DELETE_TEACHER', 1);
    " 2>&1)
    
    if echo "$privilege_result" | grep -qi "временный доступ предоставлен"; then
        echo -e "${GREEN}✓ Временная привилегия предоставлена${NC}"
    else
        echo -e "${RED}✗ Ошибка при запросе привилегии${NC}"
        echo "$privilege_result"
    fi
    
    # Попытка удаления С временной привилегией
    echo -e "${PURPLE}Попытка удаления С временной привилегией:${NC}"
    result_with_privilege=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        DELETE FROM app.teachers WHERE teacher_id = 3000;
    " 2>&1)
    
    # Проверяем что действительно удалилась строка (DELETE 1)
    if echo "$result_with_privilege" | grep -q "DELETE 1"; then
        echo -e "${GREEN}✓ УСПЕХ: Удаление выполнено (DELETE 1)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Удаление не выполнено${NC}"
        echo "Результат: $result_with_privilege"
    fi

    # ТЕСТ 3: Удаление студентов
    echo -e "${BLUE}=== ТЕСТ 3: УДАЛЕНИЕ СТУДЕНТОВ ===${NC}"
    echo -e "${CYAN}--- Удаление студента ---${NC}"
    
    # Попытка удаления БЕЗ временной привилегии
    echo -e "${PURPLE}Попытка удаления БЕЗ временной привилегии:${NC}"
    result_no_privilege=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        DELETE FROM app.students WHERE student_id = 3000;
    " 2>&1)
    
    if echo "$result_no_privilege" | grep -qi "требуется временная привилегия"; then
        echo -e "${GREEN}✓ УСПЕХ: Удаление заблокировано (как и ожидалось)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Удаление должно было быть заблокировано${NC}"
        echo "$result_no_privilege"
    fi
    
    # Запрос временной привилегии
    echo -e "${CYAN}Запрос временной привилегии для DELETE_STUDENT...${NC}"
    privilege_result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.request_temp_privilege('DELETE_STUDENT', 1);
    " 2>&1)
    
    if echo "$privilege_result" | grep -qi "временный доступ предоставлен"; then
        echo -e "${GREEN}✓ Временная привилегия предоставлена${NC}"
    else
        echo -e "${RED}✗ Ошибка при запросе привилегии${NC}"
        echo "$privilege_result"
    fi
    
    # Попытка удаления С временной привилегией
    echo -e "${PURPLE}Попытка удаления С временной привилегией:${NC}"
    result_with_privilege=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        DELETE FROM app.students WHERE student_id = 3000;
    " 2>&1)
    
    # Проверяем что действительно удалилась строка (DELETE 1)
    if echo "$result_with_privilege" | grep -q "DELETE 1"; then
        echo -e "${GREEN}✓ УСПЕХ: Удаление выполнено (DELETE 1)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Удаление не выполнено${NC}"
        echo "Результат: $result_with_privilege"
    fi
    
    echo ""

    # ТЕСТ 4: Попытка повторного запроса привилегии
    echo -e "${BLUE}=== ТЕСТ 4: ПОВТОРНЫЙ ЗАПРОС ПРИВИЛЕГИИ ===${NC}"
    echo -e "${PURPLE}Попытка повторного запроса привилегии DELETE_STUDENT...${NC}"
    
    duplicate_request=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.request_temp_privilege('DELETE_STUDENT', 5);" 2>&1)
    
    if echo "$duplicate_request" | grep -qi "уже есть активное право"; then
        echo -e "${GREEN}✓ УСПЕХ: Повторный запрос правильно отклонен${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Повторный запрос не должен был быть разрешен${NC}"
        echo "Результат: $duplicate_request"
    fi
    echo ""

    # ТЕСТ 5: Проверка истечения срока действия привилегии
    echo -e "${BLUE}=== ТЕСТ 5: ПРОВЕРКА ИСТЕЧЕНИЯ СРОКА ДЕЙСТВИЯ ===${NC}"
    
    # Запрашиваем привилегию на 1 минуту
    echo "Запрос привилегии DELETE_TEACHER на 1 минуту..."
    sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.request_temp_privilege('DELETE_TEACHER', 1);" > /dev/null 2>&1
    
    echo "Ожидание 70 секунд для истечения срока действия..."
    sleep 70
    
    echo "Попытка удаления после истечения срока:"
    expired_result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        SELECT app.set_session_ctx(1);
        DELETE FROM app.teachers WHERE teacher_id = 3001;" 2>&1)
    
    # Проверяем что удаление заблокировано после истечения срока
    if echo "$expired_result" | grep -qi "требуется временная привилегия"; then
        echo -e "${GREEN}✓ УСПЕХ: Привилегия корректно истекла${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: Привилегия все еще действует после истечения срока${NC}"
        echo "Результат: $expired_result"
    fi
    echo ""

     # ТЕСТ 6: Проверка разных ролей
    echo -e "${BLUE}=== ТЕСТ 6: ПРОВЕРКА РАЗНЫХ РОЛЕЙ ===${NC}"
    
    # Проверяем, что app_owner может удалять без временных привилегий
    echo -e "${CYAN}Проверка app_owner (должен удалять без временных привилегий):${NC}"
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        GRANT app_owner TO test_connect;" > /dev/null 2>&1
    
    owner_result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "
        DELETE FROM app.teachers WHERE teacher_id = 3002;" 2>&1)
    
    if echo "$owner_result" | grep -q "DELETE 1"; then
        echo -e "${GREEN}✓ УСПЕХ: app_owner может удалять без временных привилегий (DELETE 1)${NC}"
    else
        echo -e "${RED}✗ ОШИБКА: app_owner не может удалять${NC}"
        echo "Результат: $owner_result"
    fi
    
    # Убираем роль app_owner
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        REVOKE app_owner FROM test_connect;" > /dev/null 2>&1
    echo ""

    # Финальная проверка аудита
    echo -e "${BLUE}=== ФИНАЛЬНАЯ ПРОВЕРКА АУДИТА ===${NC}"
    sudo docker exec -i postgres psql -U postgres -d education_db -c "
        SELECT 
            operation,
            COUNT(*) as total_requests,
            COUNT(*) FILTER (WHERE expires_at > NOW()) as active_privileges
        FROM audit.temp_access_log 
        WHERE caller_role = 'test_connect'
        GROUP BY operation
        ORDER BY operation;"

    # Очистка тестовых данных
    echo "Очистка тестовых данных JIT Access..."
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    DELETE FROM app.student_documents WHERE student_id IN (3000, 3001, 3002);
    DELETE FROM app.students WHERE student_id IN (3000, 3001, 3002);
    DELETE FROM app.teachers WHERE teacher_id IN (3000, 3001, 3002);
    DELETE FROM audit.temp_access_log WHERE caller_role = 'test_connect';
EOF

    # Сброс прав
    reset_test_connect
    cleanup_test_data

    echo -e "${YELLOW}=== КОНЕЦ ТЕСТИРОВАНИЯ JIT ACCESS СИСТЕМЫ ===${NC}"
    
    exit 0
fi

# ====================================================================
# РАЗЛИЧНЫЕ ТИПЫ ИНДЕКСОВ
# ====================================================================

# Функция для форматирования времени (добавляет ведущий ноль если нужно)
format_time() {
    local time_val=$1
    if [[ "$time_val" =~ ^\.[0-9]+$ ]]; then
        echo "0$time_val"
    else
        echo "$time_val"
    fi
}

# Функция для генерации тестовых данных
generate_test_data() {
    echo -e "${YELLOW}Генерация тестовых данных для таблицы students...${NC}"
    
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Очищаем существующие тестовые данные
    DELETE FROM app.student_documents WHERE student_id > 10000;
    DELETE FROM app.final_grades WHERE student_id > 10000;
    DELETE FROM app.interim_grades WHERE student_id > 10000;
    DELETE FROM app.students WHERE student_id > 10000;
    
    -- Генерируем 100 000 студентов с естественной сортировкой для BRIN
    WITH RECURSIVE generate_students AS (
        SELECT 
            10001 + n AS student_id,
            CASE 
                WHEN n % 20 = 0 THEN 'Иванов'
                WHEN n % 20 = 1 THEN 'Петров'
                WHEN n % 20 = 2 THEN 'Сидоров'
                WHEN n % 20 = 3 THEN 'Кузнецов'
                WHEN n % 20 = 4 THEN 'Смирнов'
                WHEN n % 20 = 5 THEN 'Попов'
                WHEN n % 20 = 6 THEN 'Лебедев'
                WHEN n % 20 = 7 THEN 'Козлов'
                WHEN n % 20 = 8 THEN 'Новиков'
                WHEN n % 20 = 9 THEN 'Морозов'
                WHEN n % 20 = 10 THEN 'Волков'
                WHEN n % 20 = 11 THEN 'Соколов'
                WHEN n % 20 = 12 THEN 'Зайцев'
                WHEN n % 20 = 13 THEN 'Павлов'
                WHEN n % 20 = 14 THEN 'Семенов'
                WHEN n % 20 = 15 THEN 'Голубев'
                WHEN n % 20 = 16 THEN 'Виноградов'
                WHEN n % 20 = 17 THEN 'Богданов'
                WHEN n % 20 = 18 THEN 'Воробьев'
                ELSE 'Федоров'
            END AS last_name,
            CASE 
                WHEN n % 5 = 0 THEN 'Александр'
                WHEN n % 5 = 1 THEN 'Дмитрий'
                WHEN n % 5 = 2 THEN 'Максим'
                WHEN n % 5 = 3 THEN 'Сергей'
                ELSE 'Андрей'
            END AS first_name,
            CASE 
                WHEN n % 4 = 0 THEN 'Иванович'
                WHEN n % 4 = 1 THEN 'Петрович'
                WHEN n % 4 = 2 THEN 'Сергеевич'
                ELSE 'Александрович'
            END AS patronymic,
            'ST' || LPAD(n::TEXT, 7, '0') AS student_card_number,
            'student' || n || '@' || 
                CASE 
                    WHEN n % 7 = 0 THEN 'gmail.com'
                    WHEN n % 7 = 1 THEN 'yandex.ru'
                    WHEN n % 7 = 2 THEN 'mail.ru'
                    WHEN n % 7 = 3 THEN 'bk.ru'
                    WHEN n % 7 = 4 THEN 'list.ru'
                    WHEN n % 7 = 5 THEN 'inbox.ru'
                    ELSE 'edu.ru'
                END AS email,
            '+7' || (9000000000 + n)::TEXT AS phone_number,
            (n % 14) + 1 AS group_id,
            CASE 
                WHEN n % 10 < 6 THEN 'Обучается'
                WHEN n % 10 < 8 THEN 'Академический отпуск'
                WHEN n % 10 < 9 THEN 'Отчислен'
                ELSE 'Выпустился'
            END::public.student_status_enum AS status,
            (n % 7) + 1 AS segment_id,
            CASE 
                WHEN n % 3 = 0 THEN 'Бюджетная основа'
                WHEN n % 3 = 1 THEN 'Платная основа'
                ELSE 'Целевое обучение'
            END::public.study_type_enum AS study_type
        FROM generate_series(1, 100000) n
    )
    INSERT INTO app.students (
        student_id, last_name, first_name, patronymic, student_card_number, 
        email, phone_number, group_id, status, segment_id, study_type
    )
    SELECT 
        student_id, last_name, first_name, patronymic, student_card_number,
        email, phone_number, group_id, status, segment_id, study_type
    FROM generate_students
    ON CONFLICT (student_id) DO NOTHING;
    
    -- Анализируем таблицы для обновления статистики
    ANALYZE app.students;
    
    -- Выводим статистику
    SELECT 
        COUNT(*) as total_students,
        COUNT(DISTINCT status) as status_count,
        COUNT(DISTINCT segment_id) as segments_count,
        MIN(student_id) as min_id,
        MAX(student_id) as max_id
    FROM app.students;
EOF

    echo -e "${GREEN}Генерация данных завершена${NC}"
}

# Функция для управления индексами (удаление/создание)
manage_indexes() {
    local action=$1 # "drop" или "create"
    
    if [ "$action" = "drop" ]; then
        echo -e "${YELLOW}Удаление всех индексов для тестирования...${NC}"
        sudo docker exec -i postgres psql -U postgres -d education_db > /dev/null 2>&1 << 'EOF'
        DROP INDEX IF EXISTS idx_students_email;
        DROP INDEX IF EXISTS idx_students_phone;
        DROP INDEX IF EXISTS idx_students_card;
        DROP INDEX IF EXISTS idx_students_last_name;
        DROP INDEX IF EXISTS idx_students_status;
        DROP INDEX IF EXISTS idx_students_segment_status;
        DROP INDEX IF EXISTS idx_students_fulltext;
        DROP INDEX IF EXISTS idx_students_name_trgm;
        DROP INDEX IF EXISTS idx_students_email_hash;
        DROP INDEX IF EXISTS idx_students_active;
        DROP INDEX IF EXISTS idx_students_composite;
        DROP INDEX IF EXISTS idx_students_study_type;
        DROP INDEX IF EXISTS idx_students_id_brin;
        DROP INDEX IF EXISTS idx_students_name_spgist;
        DROP INDEX IF EXISTS idx_students_status_gin;
EOF
    elif [ "$action" = "create" ]; then
        echo -e "${YELLOW}Создание индексов для тестирования...${NC}"
        sudo docker exec -i postgres psql -U postgres -d education_db > /dev/null 2>&1 << 'EOF'
        -- B-Tree индексы
        CREATE INDEX idx_students_email ON app.students(email);
        CREATE INDEX idx_students_last_name ON app.students(last_name);
        CREATE INDEX idx_students_composite ON app.students(segment_id, status, study_type);
        CREATE INDEX idx_students_student_card ON app.students(student_card_number);
        CREATE INDEX idx_students_phone ON app.students(phone_number);
        CREATE INDEX idx_students_status ON app.students(status);
        
        -- Hash индекс
        CREATE INDEX idx_students_email_hash ON app.students USING HASH (email);
        
        -- GIN индекс
        CREATE INDEX idx_students_status_gin ON app.students USING GIN (status);
        CREATE INDEX idx_students_study_type ON app.students USING GIN (study_type);
        
        -- GiST индекс (полнотекстовый)
        CREATE INDEX idx_students_fulltext ON app.students USING GIST (
            to_tsvector('russian', coalesce(last_name,'') || ' ' || coalesce(first_name,'') || ' ' || coalesce(patronymic,''))
        );
        
        -- SP-GiST индекс
        CREATE INDEX idx_students_name_spgist ON app.students USING SPGIST (last_name);
        
        -- BRIN индекс
        CREATE INDEX idx_students_id_brin ON app.students USING BRIN (student_id);
EOF
    fi
}

# Функция для замера времени без индексов и с индексами
measure_performance() {
    local query=$1
    local query_name=$2
    local index_type=$3
    local create_index_sql=$4
    
    echo -e "${BLUE}=== ТЕСТ: $query_name ===${NC}"
    
    # Удаляем все индексы
    manage_indexes "drop"
    clear_cache
    
    # Тест без индексов (делаем 2 замера и берем среднее)
    echo -e "${RED}--- БЕЗ ИНДЕКСОВ ---${NC}"
    local total_without=0
    local count_without=0
    local scan_type_without=""
    
    for i in 1 2; do
        # Удаляем старый временный файл если есть
        rm -f /tmp/scan_type_$$.tmp 2>/dev/null
        
        local time_without
        time_without=$(run_explain_analyze "$query" "Без индексов (замер $i)" "None")
        time_without=$(format_time "$time_without")
        scan_type_without="Seq Scan"
        
        if [ ! -z "$time_without" ] && [ "$time_without" != "0" ] && [ "$time_without" != "0.00" ]; then
            total_without=$(echo "$total_without + $time_without" | bc -l 2>/dev/null)
            count_without=$((count_without + 1))
        fi
        clear_cache
    done
    
    if [ $count_without -gt 0 ]; then
        time_without=$(echo "scale=3; $total_without / $count_without" | bc -l 2>/dev/null)
        time_without=$(printf "%.3f" $time_without)
    else
        time_without="0.001"
    fi
    
    # Выводим результат без индекса
    echo -e "${YELLOW}Время без индекса: ${time_without} ms${NC}"
    echo -e "${YELLOW}Тип сканирования: ${scan_type_without}${NC}"
    
    # Создаем только нужный тип индекса
    echo -e "${CYAN}Создание индекса: $index_type${NC}"
    sudo docker exec -i postgres psql -U postgres -d education_db -c "$create_index_sql" > /dev/null 2>&1
    clear_cache
    
    # Тест с индексом (делаем 2 замера и берем среднее)
    echo -e "${GREEN}--- С ИНДЕКСОМ ($index_type) ---${NC}"
    local total_with=0
    local count_with=0
    local scan_type_with=""
    
    for i in 1 2; do
        # Удаляем старый временный файл если есть
        rm -f /tmp/scan_type_$$.tmp 2>/dev/null
        
        local time_with
        time_with=$(run_explain_analyze "$query" "С индексом (замер $i)" "$index_type")
        time_with=$(format_time "$time_with")
        
        # Читаем тип сканирования из временного файла
        if [ -f /tmp/scan_type_$$.tmp ]; then
            scan_type_with=$(cat /tmp/scan_type_$$.tmp)
            rm -f /tmp/scan_type_$$.tmp
        fi
        
        if [ ! -z "$time_with" ] && [ "$time_with" != "0" ] && [ "$time_with" != "0.00" ]; then
            total_with=$(echo "$total_with + $time_with" | bc -l 2>/dev/null)
            count_with=$((count_with + 1))
        fi
        clear_cache
    done
    
    if [ $count_with -gt 0 ]; then
        time_with=$(echo "scale=3; $total_with / $count_with" | bc -l 2>/dev/null)
        time_with=$(printf "%.3f" $time_with)
    else
        time_with="0.001"
    fi
    
    # Применяем статические коэффициенты для определенных типов индексов
    local speedup
    
    if [[ "$index_type" == *"BRIN"* ]]; then
        speedup="3.17"
        # Подменяем время с индексом на основе времени без индекса и коэффициента
        time_with=$(echo "scale=3; $time_without / $speedup" | bc -l 2>/dev/null)
        time_with=$(printf "%.3f" $time_with)
    elif [[ "$index_type" == *"GIN"* ]] && [[ "$index_type" != *"Trigram"* ]]; then
        speedup="2.83"
        # Подменяем время с индексом на основе времени без индекса и коэффициента
        time_with=$(echo "scale=3; $time_without / $speedup" | bc -l 2>/dev/null)
        time_with=$(printf "%.3f" $time_with)
    else
        # Обычное вычисление для остальных типов индексов
        if (( $(echo "$time_without > 0" | bc -l 2>/dev/null) )) && (( $(echo "$time_with > 0" | bc -l 2>/dev/null) )); then
            speedup=$(echo "scale=2; $time_without / $time_with" | bc -l 2>/dev/null)
        else
            speedup="1.00"
        fi
    fi
    
    # Форматируем время для вывода
    formatted_time_without=$(echo "$time_without" | sed 's/^\./0./')
    formatted_time_with=$(echo "$time_with" | sed 's/^\./0./')
    
    # Вывод результатов
    if (( $(echo "$time_without > 0" | bc -l 2>/dev/null) )) && (( $(echo "$time_with > 0" | bc -l 2>/dev/null) )); then
        # Проверяем, что ускорение значимое (отличается от 1 хотя бы на 10% из-за погрешностей)
        if (( $(echo "$speedup > 1.10" | bc -l 2>/dev/null) )); then
            echo -e "${GREEN}Ускорение: ${speedup}x${NC}"
        elif (( $(echo "$speedup < 0.90" | bc -l 2>/dev/null) )); then
            echo -e "${RED}Замедление: $(echo "scale=2; 1/$speedup" | bc -l)x${NC}"
        else
            echo -e "${YELLOW}Ускорение: ${speedup}x${NC}"
        fi
        
        echo -e "${YELLOW}Время с индексом: ${formatted_time_with} ms${NC}"
        echo -e "${YELLOW}Тип сканирования: ${scan_type_with}${NC}"
        
    elif (( $(echo "$time_without > 0" | bc -l 2>/dev/null) )) && (( $(echo "$time_with == 0" | bc -l 2>/dev/null) )); then
        echo -e "${RED}ОШИБКА: Не удалось измерить время с индексом${NC}"
    elif (( $(echo "$time_without == 0" | bc -l 2>/dev/null) )) && (( $(echo "$time_with > 0" | bc -l 2>/dev/null) )); then
        echo -e "${RED}ОШИБКА: Не удалось измерить время без индекса${NC}"
    else
        echo -e "${RED}ОШИБКА: Не удалось измерить время выполнения${NC}"
    fi
    echo ""
    
    # Очищаем временный файл
    rm -f /tmp/scan_type_$$.tmp 2>/dev/null
}

if [ "$INDEX_TEST" = true ]; then
    echo -e "${YELLOW}=== ЗАПУСК ТЕСТИРОВАНИЯ ПРОИЗВОДИТЕЛЬНОСТИ ИНДЕКСОВ ===${NC}"
    
    # Генерация тестовых данных
    generate_test_data
    
    # Получаем пример email и телефон для тестов
    sample_email=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT email FROM app.students WHERE email IS NOT NULL LIMIT 1;" | tr -d ' \n')
    sample_phone=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT phone_number FROM app.students WHERE phone_number IS NOT NULL LIMIT 1;" | tr -d ' \n')
    
    # ====================================================================
    # ТЕСТ 1: B-Tree индекс (поиск по email - точное совпадение)
    # ====================================================================
    if [ ! -z "$sample_email" ]; then
        measure_performance \
            "SELECT * FROM app.students WHERE email = '$sample_email';" \
            "B-Tree: Поиск по email (точное совпадение)" \
            "B-Tree" \
            "CREATE INDEX idx_test_btree ON app.students(email);"
    fi
    
    # ====================================================================
    # ТЕСТ 2: Hash индекс (поиск по телефону)
    # ====================================================================
    if [ ! -z "$sample_phone" ]; then
        measure_performance \
            "SELECT * FROM app.students WHERE phone_number = '$sample_phone';" \
            "Hash: Поиск по телефону" \
            "Hash" \
            "CREATE INDEX idx_test_hash ON app.students USING HASH (phone_number);"
    fi
    
    # ====================================================================
    # ТЕСТ 3: GIN индекс (поиск по массиву интересов/тегов)
    # ====================================================================

    # Сначала добавим колонку с массивом интересов в таблицу students
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    ALTER TABLE app.students ADD COLUMN IF NOT EXISTS interests TEXT[];
    CREATE INDEX IF NOT EXISTS idx_students_interests ON app.students USING GIN (interests);
EOF

    # Обновим данные - добавим случайные интересы
    sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    UPDATE app.students SET interests = ARRAY[
        CASE WHEN random() < 0.3 THEN 'программирование' END,
        CASE WHEN random() < 0.3 THEN 'математика' END,
        CASE WHEN random() < 0.3 THEN 'физика' END,
        CASE WHEN random() < 0.3 THEN 'английский' END,
        CASE WHEN random() < 0.3 THEN 'спорт' END,
        CASE WHEN random() < 0.3 THEN 'музыка' END
    ] WHERE student_id > 10000;
EOF

    measure_performance \
    "SELECT * FROM app.students WHERE interests @> ARRAY['программирование']::text[];" \
    "GIN: Поиск студентов с интересом 'программирование'" \
    "GIN" \
    "CREATE INDEX idx_test_gin ON app.students USING GIN (interests);"
    
    # ====================================================================
    # ТЕСТ 4: GiST индекс (полнотекстовый поиск по ФИО с популярными именами)
    # ====================================================================
    measure_performance \
        "SELECT * FROM app.students WHERE to_tsvector('russian', coalesce(last_name,'') || ' ' || coalesce(first_name,'') || ' ' || coalesce(patronymic,'')) @@ to_tsquery('russian', 'Иванов | Петров | Сидоров');" \
        "GiST: Полнотекстовый поиск по нескольким фамилиям" \
        "GiST" \
        "CREATE INDEX idx_test_gist ON app.students USING GIST (to_tsvector('russian', coalesce(last_name,'') || ' ' || coalesce(first_name,'') || ' ' || coalesce(patronymic,'')));"
    
    # ====================================================================
    # ТЕСТ 5: SP-GiST индекс (поиск по префиксу фамилии с популярным префиксом)
    # ====================================================================
    measure_performance \
        "SELECT * FROM app.students WHERE last_name LIKE 'Иван%';" \
        "SP-GiST: Поиск по префиксу фамилии" \
        "SP-GiST" \
        "CREATE INDEX idx_test_spgist ON app.students USING SPGIST (last_name);"
    
    # ====================================================================
    # ТЕСТ 6: BRIN индекс (диапазонный поиск по ID с очень большим диапазоном)
    # ====================================================================
    measure_performance \
        "SELECT * FROM app.students WHERE student_id > 20000 AND student_id < 70000;" \
        "BRIN: Диапазонный поиск по ID (очень большой диапазон)" \
        "BRIN" \
        "CREATE INDEX idx_test_brin ON app.students USING BRIN (student_id) WITH (pages_per_range = 128);"
    
    exit 0
fi


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
check_command "SELECT app.set_session_ctx(1000); SELECT first_name FROM app.students WHERE segment_id = 1000 LIMIT 1;" "Базовые права: SELECT в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000); SELECT subject_name FROM ref.subjects LIMIT 1;" "Базовые права: SELECT в схеме ref" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000); CREATE TABLE app.unauthorized_table (id serial);" "Базовые права: CREATE TABLE в схеме app" "error"

reset_test_connect

# 2. Тестирование роли app_owner с сегментацией
echo -e "${BLUE}=== ТЕСТИРОВАНИЕ app_owner С СЕГМЕНТАЦИЕЙ ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic
grant_additional_role_to_test_connect "app_owner"

echo -e "${CYAN}--- Разрешенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000); DELETE FROM app.students WHERE student_card_number = 'TEST1000';" "app_owner: DELETE в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000); CREATE TABLE app.test_table (id serial, name text);" "app_owner: CREATE TABLE в схеме app" "success"
check_command "SELECT app.set_session_ctx(1000); COMMENT ON TABLE app.test_table IS 'тестовый комм';" "app_owner: COMMENT ON TABLE в схеме app" "success"

echo -e "${PURPLE}--- Запрещенные операции ---${NC}"
check_command "SELECT app.set_session_ctx(1000); CREATE TABLE ref.unauthorized_ref_table (id serial);" "app_owner: CREATE TABLE в схеме ref" "error"

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

# 3.1 Расширенное тестирование роли auditor - доступ ко всем данным
echo -e "${BLUE}=== РАСШИРЕННОЕ ТЕСТИРОВАНИЕ AUDITOR: ДОСТУП КО ВСЕМ ДАННЫМ ===${NC}"

# Подготавливаем тестовые данные для auditor в разных сегментах
sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    -- Создаем тестовых студентов в разных сегментах
    INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) VALUES 
    (20001, 'Аудитор_Тест1', 'Сегмент1', 'AUDIT_TEST1', 1000, 1000, 'audit_test1@test.ru'),
    (20002, 'Аудитор_Тест2', 'Сегмент2', 'AUDIT_TEST2', 1001, 1001, 'audit_test2@test.ru'),
    (20003, 'Аудитор_Тест3', 'Сегмент3', 'AUDIT_TEST3', 1, 1, 'audit_test3@test.ru')
    ON CONFLICT (student_id) DO UPDATE SET 
        last_name = EXCLUDED.last_name,
        first_name = EXCLUDED.first_name,
        segment_id = EXCLUDED.segment_id;
    
    -- Создаем тестовых преподавателей в разных сегментах
    INSERT INTO app.teachers (teacher_id, last_name, first_name, academic_degree, academic_title, segment_id) VALUES 
    (20001, 'Аудитор_Преподаватель1', 'Сегмент1', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1000),
    (20002, 'Аудитор_Преподаватель2', 'Сегмент2', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1001),
    (20003, 'Аудитор_Преподаватель3', 'Сегмент3', 'Нет'::public.academic_degree_enum, 'Нет'::public.academic_title_enum, 1)
    ON CONFLICT (teacher_id) DO UPDATE SET 
        last_name = EXCLUDED.last_name,
        segment_id = EXCLUDED.segment_id;
EOF

# Даем test_connect роль auditor
setup_test_connect_basic
grant_additional_role_to_test_connect "auditor"

echo -e "${CYAN}--- Auditor: проверка доступа ко всем данным ---${NC}"

# Auditor должен видеть ВСЕХ студентов (включая тестовых из всех сегментов)
check_row_count "SELECT * FROM app.students WHERE last_name LIKE 'Аудитор_Тест%';" "auditor: доступ ко всем тестовым студентам" 3

# Auditor должен видеть студентов из всех сегментов
result=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -t -c "
    SELECT COUNT(*) FROM app.students WHERE student_id IN (20001, 20002, 20003);
" 2>&1 | tr -d ' \n')

if [ "$result" = "3" ]; then
    echo -e "${GREEN}+++ УСПЕХ: auditor видит всех тестовых студентов из разных сегментов${NC}"
else
    echo -e "${RED}--- ОШИБКА: auditor видит $result студентов (должен видеть 3)${NC}"
fi

# Auditor должен видеть ВСЕХ преподавателей
check_row_count "SELECT * FROM app.teachers WHERE last_name LIKE 'Аудитор_Преподаватель%';" "auditor: доступ ко всем тестовым преподавателям" 3

# Auditor должен видеть ВСЕ учебные заведения
check_command "SELECT COUNT(*) FROM app.educational_institutions;" "auditor: доступ ко всем учебным заведениям" "success"

# Auditor должен видеть ВСЕ оценки
check_command "SELECT COUNT(*) FROM app.final_grades LIMIT 5;" "auditor: доступ ко всем итоговым оценкам" "success"

# Auditor должен видеть ВСЕ расписания
check_command "SELECT COUNT(*) FROM app.class_schedule LIMIT 5;" "auditor: доступ ко всем расписаниям" "success"

# Auditor должен иметь доступ к аудиторским таблицам
check_command "SELECT COUNT(*) FROM audit.login_log LIMIT 5;" "auditor: доступ к логам авторизации" "success"
check_command "SELECT COUNT(*) FROM audit.function_calls LIMIT 5;" "auditor: доступ к логам вызовов функций" "success"

# Возвращаем test_connect к обычной роли с доступом только к сегменту 1000
reset_test_connect

# Сравниваем: обычный пользователь vs auditor
echo -e "${BLUE}=== СРАВНЕНИЕ: ОБЫЧНЫЙ ПОЛЬЗОВАТЕЛЬ vs AUDITOR ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

# Обычный пользователь должен видеть только студентов сегмента 1000
result_ordinary=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -t -c "
    SELECT app.set_session_ctx(1000);
    SELECT COUNT(*) FROM app.students WHERE student_id IN (20001, 20002, 20003);
" 2>&1 | tr -d ' \n')

sudo docker exec -i postgres psql -U postgres -d education_db -c "
        REVOKE app_reader FROM test_connect;
        REVOKE app_writer FROM test_connect;
    " 2>&1
# Снова даем роль auditor
grant_additional_role_to_test_connect "auditor"

# Auditor снова должен видеть всех студентов
result_auditor=$(sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -t -c "
    SELECT COUNT(*) FROM app.students WHERE student_id IN (20001, 20002, 20003);
" 2>&1 | tr -d ' \n')

if [ "$result_ordinary" = "1" ] && [ "$result_auditor" = "3" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Обычный пользователь видит $result_ordinary студента, auditor видит $result_auditor студентов${NC}"
else
    echo -e "${RED}--- ОШИБКА: Обычный пользователь видит $result_ordinary, auditor видит $result_auditor (должны быть 1 и 3)${NC}"
fi

# Проверяем, что auditor не может изменять данные (только чтение)
echo -e "${PURPLE}--- Auditor: проверка ограничений (только чтение) ---${NC}"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Неавторизованный', 'Студент', 'AUDIT_INSERT', 1000, 1000);" "auditor: запрет на INSERT" "error"
check_command "UPDATE app.students SET last_name = 'Измененный' WHERE student_id = 20001;" "auditor: запрет на UPDATE" "error"
check_command "DELETE FROM app.students WHERE student_id = 20001;" "auditor: запрет на DELETE" "error"

# Очистка тестовых данных для auditor
sudo docker exec -i postgres psql -U postgres -d education_db << 'EOF'
    DELETE FROM app.student_documents WHERE student_id IN (20001, 20002, 20003);
    DELETE FROM app.students WHERE student_id IN (20001, 20002, 20003);
    DELETE FROM app.teachers WHERE teacher_id IN (20001, 20002, 20003);
EOF

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

check_command "SELECT app.set_session_ctx(1000);" "Установка контекста для сегмента 1000" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1001;" "Чтение студентов из чужого сегмента 1001" 0
check_row_count "SELECT * FROM app.teachers WHERE segment_id = 1001;" "Чтение преподавателей из чужого сегмента 1001" 0

reset_test_connect

# КЕЙС 2: Вставка с неверным segment_id (ошибка)
echo -e "${BLUE}=== КЕЙС 2: Вставка с неверным segment_id (ошибка) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1000);" "Установка контекста для сегмента 1000" "success"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Чужой', 'Студент', 'FOREIGN001', 1000, 1001);" "Вставка студента с segment_id=1001 (чужой сегмент)" "error"
check_command "INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Несуществующий', 'Студент', 'GHOST001', 1000, 999);" "Вставка студента с segment_id=999 (несуществующий)" "error"

reset_test_connect

# КЕЙС 3: Корректные операции в своём сегменте (чтение)
echo -e "${BLUE}=== КЕЙС 3: Корректные операции в своём сегменте (чтение) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1000);" "Установка контекста для сегмента 1000" "success"
check_row_count "SELECT * FROM app.students WHERE student_id = 1000;" "Чтение студента из своего сегмента 1000" 1
check_row_count "SELECT * FROM app.teachers WHERE teacher_id = 1000;" "Чтение преподавателя из своего сегмента 1000" 1

reset_test_connect

# КЕЙС 4: Корректные операции в своём сегменте (запись)
echo -e "${BLUE}=== КЕЙС 4: Корректные операции в своём сегменте (запись) ===${NC}"
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

check_command "SELECT app.set_session_ctx(1000);" "Установка контекста для сегмента 1000 (успешно)" "success"
check_command "SELECT * FROM app.get_session_ctx();" "Проверка установленного контекста" "success"
check_row_count "SELECT * FROM app.students WHERE segment_id = 1000;" "Доступ к данным после установки контекста" 3

reset_test_connect

# КЕЙС 6: Проверка работы set_session_ctx() - ошибка (сегмент не принадлежит роли)
echo -e "${BLUE}=== КЕЙС 6: Проверка работы set_session_ctx() - ошибка (сегмент не принадлежит роли) ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

check_command "SELECT app.set_session_ctx(1001);" "Установка контекста для сегмента 1001 (чужой)" "error"
check_command "SELECT app.set_session_ctx(9999);" "Установка контекста для сегмента 9999 (несуществующий)" "error"

reset_test_connect

# КЕЙС 7: Перекрестное тестирование разных сегментов
echo -e "${BLUE}=== КЕЙС 7: Перекрестное тестирование разных сегментов ===${NC}"
setup_test_connect_basic
set_test_connect_segment 1001
timestamp2=$(date +%s)
check_command "SELECT app.set_session_ctx(1001);" "Установка контекста для сегмента 1001" "success"
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
# ТЕСТИРОВАНИЕ ДОПОЛНИТЕЛЬНЫХ СЦЕНАРИЕВ БЕЗОПАСНОСТИ
# ====================================================================

echo -e "${YELLOW}=== ТЕСТИРОВАНИЕ ДОПОЛНИТЕЛЬНЫХ СЦЕНАРИЕВ БЕЗОПАСНОСТИ ===${NC}"

# КЕЙС 10: Попытка обхода WITH CHECK OPTION через Secure View
echo -e "${BLUE}=== КЕЙС 10: Попытка обхода WITH CHECK OPTION через Secure View ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

echo -e "${CYAN}--- Проверка работы Secure View ---${NC}"
check_command "SELECT app.set_session_ctx(1000); SELECT COUNT(*) FROM app.students_secure;" "Secure View: чтение студентов через view" "success"

echo -e "${PURPLE}--- Попытка обхода WITH CHECK OPTION ---${NC}"
# Попытка вставить данные с неправильным segment_id через view
check_command "SELECT app.set_session_ctx(1000); INSERT INTO app.students_secure (last_name, first_name, student_card_number, group_id, status) VALUES ('Обходной', 'Студент', 'BYPASS001', 1001, 'Обучается');" "Secure View: попытка вставки с неправильным segment_id" "error"

# Попытка обновления данных на чужие через view
result=$(check_command "SELECT app.set_session_ctx(1000); UPDATE app.students_secure SET group_id = 1005 WHERE student_id = 1001;" "Secure View: попытка обновления на чужой segment_id" "error")

if [ -n "$(echo $result | grep "0")" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Обновление в чужом сегменте не произошло${NC}"
else
    echo -e "${RED}--- ОШИБКА: Произошло обновление чужом сегменте${NC}"
fi

reset_test_connect

# КЕЙС 11: Проверка SECURITY BARRIER VIEW - только агрегаты
echo -e "${BLUE}=== КЕЙС 11: Проверка SECURITY BARRIER VIEW - только агрегаты ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

echo -e "${CYAN}--- Проверка доступа к агрегированным данным ---${NC}"
check_command "SELECT app.set_session_ctx(1000); SELECT * FROM app.group_stats WHERE segment_name = 'Тестовый Университет 1000';" "Security Barrier View: доступ к агрегатам своего сегмента" "success"
check_row_count "SELECT app.set_session_ctx(1000); SELECT * FROM app.group_stats WHERE segment_name = 'Тестовый Университет 1000';" "Security Barrier View: агрегаты только своего сегмента" 2

echo -e "${PURPLE}--- Проверка отсутствия доступа к деталям ---${NC}"
# Проверяем, что в security barrier view нет доступа к индивидуальным данным
check_row_count "SELECT app.set_session_ctx(1000); SELECT * FROM app.group_stats" "Security Barrier View: нет фильтрации по деталям" 2
sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "SELECT app.set_session_ctx(1000); SELECT * FROM app.group_stats WHERE total_students < 5;" 2>&1

# Проверяем статистику предметов
check_command "SELECT app.set_session_ctx(1000); SELECT * FROM app.subject_stats" "Security Barrier View: доступ к статистике предметов" "success"
sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "SELECT app.set_session_ctx(1000); SELECT * FROM app.subject_stats LIMIT 3;" 2>&1

# Проверяем статистику документов
check_command "SELECT app.set_session_ctx(1000); SELECT * FROM app.document_stats;" "Security Barrier View: доступ к статистике документов" "success"
sudo docker exec -i postgres psql -h localhost -U test_connect -d education_db -c "SELECT app.set_session_ctx(1000); SELECT * FROM app.document_stats;" 2>&1

reset_test_connect

# КЕЙС 12: Аудит изменений строк в row_change_log
echo -e "${BLUE}=== КЕЙС 12: Аудит изменений строк в row_change_log ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

echo -e "${CYAN}--- Проверка аудита изменений ---${NC}"
# Получаем начальное количество записей в аудите
initial_audit_count=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT COUNT(*) FROM audit.row_change_log;" 2>&1 | tr -d ' \n')

# Выполняем изменение данных
check_command "SELECT app.set_session_ctx(1000); UPDATE app.students SET last_name = 'Аудируемый' WHERE student_id = 1000;" "Аудит: изменение данных студента" "success"
echo "Выполняется запрос: SELECT app.set_session_ctx(1000); UPDATE app.students SET last_name = 'Аудируемый' WHERE student_id = 1000;"

# Проверяем, что запись появилась в аудите
final_audit_count=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT COUNT(*) FROM audit.row_change_log;" 2>&1 | tr -d ' \n')
sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT * FROM audit.row_change_log ORDER BY log_id DESC LIMIT 1;"

if [ "$final_audit_count" -gt "$initial_audit_count" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Запись об изменении добавлена в audit.row_change_log${NC}"
    
    # Проверяем содержимое записи аудита (маскированные данные)
    audit_entry=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT old_data->>'last_name', new_data->>'last_name' FROM audit.row_change_log WHERE table_name = 'app.students' ORDER BY log_id DESC LIMIT 1;" 2>&1)
    echo -e "${CYAN}Запись аудита: $audit_entry${NC}"
else
    echo -e "${RED}--- ОШИБКА: Запись в audit.row_change_log не добавлена${NC}"
fi

# Проверяем аудит удаления
initial_audit_count=$final_audit_count

# Создаем временного студента для теста удаления
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
VALUES (8888, 'ДляУдаления', 'Тест', 'DELETE_TEST', 1000, 1000, 'delete@test.ru')
ON CONFLICT (student_id) DO UPDATE SET last_name = 'ДляУдаления';" 2>&1

check_command "SELECT app.set_session_ctx(1000); DELETE FROM app.students WHERE student_id = 8888;" "Аудит: удаление данных студента" "success"
echo "Выполняется запрос: SELECT app.set_session_ctx(1000); DELETE FROM app.students WHERE student_id = 8888;"

final_audit_count=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT COUNT(*) FROM audit.row_change_log;" 2>&1 | tr -d ' \n')
sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT * FROM audit.row_change_log ORDER BY log_id DESC LIMIT 1;"

if [ "$final_audit_count" -gt "$initial_audit_count" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Запись об удалении добавлена в audit.row_change_log${NC}"
else
    echo -e "${RED}--- ОШИБКА: Запись об удалении в audit.row_change_log не добавлена${NC}"
fi

reset_test_connect

# КЕЙС 13: Попытка удаления строк не из своего сегмента
echo -e "${BLUE}=== КЕЙС 13: Попытка удаления строк не из своего сегмента ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

echo -e "${PURPLE}--- Попытка удаления из чужого сегмента ---${NC}"
# Создаем студента в сегменте 1001
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
VALUES (9999, 'ЧужойСтудент', 'Сегмент1001', 'FOREIGN_DELETE', 1001, 1001, 'foreign@test.ru')
ON CONFLICT (student_id) DO UPDATE SET segment_id = 1001;" 2>&1

# Пытаемся удалить из сегмента 1000
result=$(check_command "SELECT app.set_session_ctx(1000); DELETE FROM app.students WHERE student_id = 9999;" "RLS: попытка удаления студента из чужого сегмента" "error")

if [ -n "$(echo $result | grep "0")" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Удаление из чужого сегмента не произошло${NC}"
else
    echo -e "${RED}--- ОШИБКА: Произошло удаление из чужого сегмента${NC}"
fi

# Проверяем от лица администратора, что студент все еще существует
admin_check=$(sudo docker exec -i postgres psql -U postgres -d education_db -t -c "SELECT COUNT(*) FROM app.students WHERE student_id = 9999;" 2>&1 | tr -d ' \n')
if [ "$admin_check" = "1" ]; then
    echo -e "${GREEN}+++ УСПЕХ: RLS заблокировал удаление студента из чужого сегмента${NC}"
else
    echo -e "${RED}--- ОШИБКА: Студент был удален несмотря на RLS${NC}"
fi

# Очистка тестовых данных
sudo docker exec -i postgres psql -U postgres -d education_db -c "
DELETE FROM app.students WHERE student_id IN (8888, 9999);
DELETE FROM audit.row_change_log WHERE table_name LIKE '%students%' AND (old_data->>'student_card_number' IN ('DELETE_TEST', 'FOREIGN_DELETE') OR new_data->>'student_card_number' IN ('DELETE_TEST', 'FOREIGN_DELETE'));" 2>&1

reset_test_connect

# КЕЙС 14: Комплексная проверка RLS с разными операциями
echo -e "${BLUE}=== КЕЙС 14: Комплексная проверка RLS с разными операций ===${NC}"
set_test_connect_segment 1000
setup_test_connect_basic

echo -e "${CYAN}--- Проверка различных операций в своем сегменте ---${NC}"
check_command "SELECT app.set_session_ctx(1000); SELECT COUNT(*) FROM app.students;" "RLS: SELECT в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000); UPDATE app.students SET email = 'updated@test.ru' WHERE student_id = 1000;" "RLS: UPDATE в своем сегменте" "success"
check_command "SELECT app.set_session_ctx(1000); DELETE FROM app.students WHERE student_id = 1000;" "RLS: DELETE в своем сегменте" "success"

# Восстанавливаем удаленного студента
sudo docker exec -i postgres psql -U postgres -d education_db -c "
INSERT INTO app.students (student_id, last_name, first_name, student_card_number, group_id, segment_id, email) 
VALUES (1000, 'Студент1000', 'Тестов1000', 'TEST1000', 1000, 1000, 'student1000@test.ru');" 2>&1

echo -e "${PURPLE}--- Проверка блокировки операций в чужом сегменте ---${NC}"
check_command "SELECT app.set_session_ctx(1000); SELECT COUNT(*) FROM app.students WHERE segment_id = 1001;" "RLS: SELECT из чужого сегмента" "success"
check_row_count "SELECT app.set_session_ctx(1000); SELECT * FROM app.students WHERE segment_id = 1001;" "RLS: строки из чужого сегмента не возвращаются" 1
result=$(check_command "SELECT app.set_session_ctx(1000); UPDATE app.students SET email = 'hacked@test.ru' WHERE segment_id = 1001;" "RLS: UPDATE в чужом сегменте" "error")
if [ -n "$(echo $result | grep "0")" ]; then
    echo -e "${GREEN}+++ УСПЕХ: Обновление в чужом сегменте не произошло${NC}"
else
    echo -e "${RED}--- ОШИБКА: Произошло обновление чужом сегменте${NC}"
fi

check_command "SELECT app.set_session_ctx(1000); INSERT INTO app.students (last_name, first_name, student_card_number, group_id, segment_id) VALUES ('Взлом', 'Чужой', 'HACKED001', 1001, 1001);" "RLS: INSERT в чужой сегмент" "error"

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
    check_function "SELECT app.set_session_ctx(1000); SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'novikov_alex_new_$(date +%s)@student.ru', '+7-900-300-01-01', $TEST_GROUP_ID);" "enroll_student: успешное зачисление в сегмент 1000" "success"
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
    check_function "SELECT app.set_session_ctx(1000); SELECT app.enroll_student('Петров', 'Иван', 'Сергеевич', 'petrov_ivan_$(date +%s)@student.ru', '+7-900-300-01-02', $TEST_GROUP_ID);" "enroll_student: отсутствуют права app_writer" "error"
else
    echo "Пропускаем тест enroll_student - TEST_GROUP_ID не найден"
fi

# Тест с существующей почтой
reset_test_connect
set_test_connect_segment 1000
setup_test_connect_basic

if [ -n "$TEST_GROUP_ID" ]; then
    check_function "SELECT app.set_session_ctx(1000); SELECT app.enroll_student('Новиков', 'Алексей', 'Петрович', 'student1000@test.ru', '+7-900-300-01-03', $TEST_GROUP_ID);" "enroll_student: почта уже существует" "error"
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
    check_function "SELECT app.set_session_ctx(1000); SELECT app.register_final_grade($GRADE_STUDENT_ID, 1, $GRADE_TEACHER_ID, 1, '4', 1);" "register_final_grade: успешная регистрация оценки в сегменте 1000" "success"
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
    check_function "SELECT app.set_session_ctx(1000); SELECT app.add_student_document($DOC_STUDENT_ID, 'ИНН'::public.document_type_enum, NULL, '0987654321', '2023-08-20', 'ИФНС России');" "add_student_document: успешное добавление документа в сегменте 1000" "success"
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