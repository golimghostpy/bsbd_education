#!/bin/bash

# Параметры подключения
DB_NAME="education_db"
DB_USER="postgres"
DB_PASSWORD="1234qwer"
DB_HOST="localhost"
DB_PORT="5432"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для выполнения SQL с полным выводом
execute_sql() {
    local sql="$1"
    local description="$2"
    
    echo -e "${YELLOW}▶ $description${NC}"
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "$sql" 2>/dev/null
    echo ""
}

# Функция для получения одного значения
get_value() {
    local sql="$1"
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -A -c "$sql" 2>/dev/null | head -1
}

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}    ТЕСТ ТРИГГЕРА ОБНОВЛЕНИЯ СКИДОК    ${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

# 1. Находим студента со статусом "Обучается"
STUDENT_ID=$(get_value "
    SELECT s.student_id 
    FROM app.students s
    WHERE s.study_type = 'Платная основа' 
      AND s.status = 'Обучается'
    ORDER BY s.gpa ASC NULLS LAST
    LIMIT 1;
")

if [ -z "$STUDENT_ID" ]; then
    echo -e "${RED}Ошибка: не найден студент со статусом 'Обучается'${NC}"
    exit 1
fi

STUDENT_INFO=$(get_value "
    SELECT s.last_name || ' ' || s.first_name
    FROM app.students s WHERE s.student_id = $STUDENT_ID;
")
echo -e "${GREEN}Тестовый студент:${NC} $STUDENT_INFO (ID: $STUDENT_ID)"
echo ""

# 2. Текущие значения ДО вставки (полный SELECT)
execute_sql "
    SELECT 
        s.student_id,
        s.last_name || ' ' || s.first_name AS student_name,
        ROUND(s.gpa, 2) AS current_gpa,
        COALESCE(sd.current_discount_percent, 0) AS discount_percent,
        s.status,
        s.study_type,
        to_char(sd.last_updated, 'DD.MM.YYYY HH24:MI:SS') AS last_updated
    FROM app.students s
    LEFT JOIN app.student_discounts sd ON s.student_id = sd.student_id 
        AND sd.semester = EXTRACT(YEAR FROM CURRENT_DATE)::INT * 2
    WHERE s.student_id = $STUDENT_ID;
" "ДАННЫЕ ДО ВСТАВКИ ОЦЕНКИ"

# 3. Добавляем отличную оценку
TEACHER_ID=$(get_value "SELECT teacher_id FROM app.teachers ORDER BY random() LIMIT 1;")
SUBJECT_ID=$(get_value "SELECT subject_id FROM ref.subjects ORDER BY random() LIMIT 1;")

GRADE_ID=$(get_value "
    INSERT INTO app.final_grades (
        student_id, subject_id, teacher_id, final_grade_type_id, 
        final_grade_value, grade_date, semester, segment_id
    )
    SELECT 
        $STUDENT_ID,
        $SUBJECT_ID,
        $TEACHER_ID,
        1,
        '5',
        CURRENT_DATE,
        EXTRACT(YEAR FROM CURRENT_DATE)::INT * 2,
        segment_id
    FROM app.students WHERE student_id = $STUDENT_ID
    RETURNING final_grade_id;
")

echo -e "${GREEN}✓ Добавлена оценка 5 (ID: $GRADE_ID)${NC}"
sleep 1

# 4. Значения ПОСЛЕ вставки (полный SELECT)
execute_sql "
    SELECT 
        s.student_id,
        s.last_name || ' ' || s.first_name AS student_name,
        ROUND(s.gpa, 2) AS current_gpa,
        COALESCE(sd.current_discount_percent, 0) AS discount_percent,
        s.status,
        s.study_type,
        to_char(sd.last_updated, 'DD.MM.YYYY HH24:MI:SS') AS last_updated,
        sd.previous_discount_percent AS previous_discount,
        sd.last_calculated_gpa
    FROM app.students s
    LEFT JOIN app.student_discounts sd ON s.student_id = sd.student_id 
        AND sd.semester = EXTRACT(YEAR FROM CURRENT_DATE)::INT * 2
    WHERE s.student_id = $STUDENT_ID;
" "ДАННЫЕ ПОСЛЕ ВСТАВКИ ОЦЕНКИ"

# 5. Показываем добавленную оценку
execute_sql "
    SELECT 
        fg.final_grade_id,
        sub.subject_name,
        fg.final_grade_value,
        fg.grade_date,
        t.last_name || ' ' || t.first_name AS teacher_name
    FROM app.final_grades fg
    JOIN ref.subjects sub ON fg.subject_id = sub.subject_id
    JOIN app.teachers t ON fg.teacher_id = t.teacher_id
    WHERE fg.final_grade_id = $GRADE_ID;
" "ДОБАВЛЕННАЯ ОЦЕНКА"

# 6. Проверка лога аудита
execute_sql "
    SELECT 
        call_time,
        function_name,
        input_params->>'student_id' AS student_id,
        input_params->>'old_discount' AS old_discount,
        input_params->>'new_discount' AS new_discount,
        input_params->>'gpa' AS gpa
    FROM audit.function_calls 
    WHERE function_name = 'update_student_discount_from_grades'
      AND input_params->>'student_id' = '$STUDENT_ID'
      AND call_time > NOW() - INTERVAL '1 minute'
    ORDER BY call_time DESC;
" "ЗАПИСИ В АУДИТЕ"

# 7. Финальный статус
echo -e "${BLUE}----------------------------------------------${NC}"
echo -e "${GREEN}ТЕСТ ЗАВЕРШЕН${NC}"
echo -e "${BLUE}----------------------------------------------${NC}"