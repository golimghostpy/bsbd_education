#!/bin/bash

# ============================================================================
# Скрипт для тестирования производительности шифрования (все удаления в конце)
# ============================================================================

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Конфигурация
CONTAINER_NAME="postgres"
DB_NAME="education_db"
DB_USER="postgres"
export PGPASSWORD="1234qwer"
TEST_STUDENT_ID=999999
ROWS=1000

# Функция для выполнения psql команд
docker_psql() {
    sudo docker exec -i -e PGPASSWORD="$PGPASSWORD" $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -q -t "$@" 2>&1
}

# Функция для выполнения psql с таймингом
measure_time() {
    local sql="$1"
    local output
    local time_ms
    output=$(sudo docker exec -i -e PGPASSWORD="$PGPASSWORD" $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -q -c "\\timing" -c "$sql" 2>&1)
    if echo "$output" | grep -qi "error"; then
        echo "ERROR: $output" >&2
        return 1
    fi
    time_ms=$(echo "$output" | grep -oE 'Time: [0-9.]+ ms' | head -1 | awk '{print $2}')
    if [ -z "$time_ms" ]; then
        echo "ERROR: Cannot parse time from output: $output" >&2
        return 1
    fi
    echo "$time_ms"
}

# Ожидание готовности PostgreSQL
wait_for_db() {
    echo -e "  ${YELLOW}▶ Ожидание готовности PostgreSQL...${NC}" >&2
    local retries=30
    local wait=2
    while [ $retries -gt 0 ]; do
        if sudo docker exec $CONTAINER_NAME pg_isready -U $DB_USER -d $DB_NAME >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ PostgreSQL готов${NC}" >&2
            return 0
        fi
        sleep $wait
        retries=$((retries - 1))
    done
    echo -e "  ${RED}✗ PostgreSQL не отвечает${NC}" >&2
    return 1
}

# Включение/отключение триггера шифрования
toggle_encryption() {
    local action=$1
    if [ "$action" == "off" ]; then
        echo -e "  ${YELLOW}▶ Отключение шифрования (удаление триггера)${NC}" >&2
        docker_psql -c "DROP TRIGGER IF EXISTS trg_encrypt_student_documents_asymmetric ON app.student_documents;" >/dev/null
        echo -e "  ${GREEN}✓ Триггер удален${NC}" >&2
    elif [ "$action" == "on" ]; then
        echo -e "  ${YELLOW}▶ Включение шифрования (создание триггера)${NC}" >&2
        local trigger_exists=$(docker_psql -c "SELECT 1 FROM pg_trigger WHERE tgname = 'trg_encrypt_student_documents_asymmetric' AND tgrelid = 'app.student_documents'::regclass;" | xargs)
        if [ "$trigger_exists" == "1" ]; then
            echo -e "  ${GREEN}✓ Триггер уже существует${NC}" >&2
            return 0
        fi
        local func_exists=$(docker_psql -c "SELECT 1 FROM pg_proc WHERE proname = 'encrypt_student_documents_asymmetric' AND pronamespace = 'app'::regnamespace;" | xargs)
        if [ "$func_exists" != "1" ]; then
            echo -e "  ${RED}✗ Функция app.encrypt_student_documents_asymmetric() не найдена. Триггер не может быть создан.${NC}" >&2
            exit 1
        fi
        docker_psql -c "
            CREATE TRIGGER trg_encrypt_student_documents_asymmetric
            BEFORE INSERT OR UPDATE OF document_series, document_number ON app.student_documents
            FOR EACH ROW
            EXECUTE FUNCTION app.encrypt_student_documents_asymmetric();
        " >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Триггер создан${NC}" >&2
        else
            echo -e "  ${RED}✗ Ошибка создания триггера${NC}" >&2
            exit 1
        fi
    else
        echo -e "  ${RED}Неверное действие для toggle_encryption${NC}" >&2
        exit 1
    fi
}

# Включение/отключение SSL
toggle_ssl() {
    local action=$1
    local conf_file="/var/lib/postgresql/data/postgresql.conf"
    
    if [ "$action" == "off" ]; then
        echo -e "  ${YELLOW}▶ Отключение SSL${NC}" >&2
        sudo docker exec $CONTAINER_NAME bash -c "sed -i 's/^#*ssl =.*/ssl = off/' $conf_file"
    elif [ "$action" == "on" ]; then
        echo -e "  ${YELLOW}▶ Включение SSL${NC}" >&2
        sudo docker exec $CONTAINER_NAME bash -c "sed -i 's/^#*ssl =.*/ssl = on/' $conf_file"
    else
        echo -e "  ${RED}Неверное действие${NC}" >&2
        exit 1
    fi
    echo -e "  ${YELLOW}▶ Перезапуск контейнера PostgreSQL...${NC}" >&2
    sudo docker restart $CONTAINER_NAME >/dev/null
    wait_for_db
}

# Подготовка тестового студента
prepare_test_student() {
    echo -e "  ${YELLOW}▶ Подготовка тестового студента (ID=$TEST_STUDENT_ID)${NC}" >&2
    local exists=$(docker_psql -c "SELECT 1 FROM app.students WHERE student_id = $TEST_STUDENT_ID;" | xargs)
    if [ "$exists" != "1" ]; then
        docker_psql -c "
            INSERT INTO app.students (student_id, last_name, first_name, patronymic, student_card_number, email, phone_number, group_id, status, study_type, segment_id)
            VALUES ($TEST_STUDENT_ID, 'Тест', 'Тест', 'Тест', 'TEST123', 'test@test.com', '123', 1, 'Обучается', 'Платная основа', 1);
        " >/dev/null
        echo -e "  ${GREEN}✓ Тестовый студент создан${NC}" >&2
    else
        echo -e "  ${GREEN}✓ Тестовый студент уже существует${NC}" >&2
    fi
}

# Вставка тестовых данных с префиксом
insert_test_data() {
    local prefix=$1
    local encryption_mode=$2
    local insert_sql
    local count
    
    echo -e "  ${YELLOW}▶ Генерация и вставка $ROWS строк (префикс '$prefix', шифрование $encryption_mode)${NC}" >&2
    
    insert_sql="
        INSERT INTO app.student_documents (student_id, document_type, document_series, document_number, issue_date, issuing_authority, segment_id)
        SELECT
            $TEST_STUDENT_ID,
            'Паспорт'::public.document_type_enum,
            convert_to('${prefix}_SERIES_' || i, 'UTF8'),
            convert_to('${prefix}_NUMBER_' || i, 'UTF8'),
            CURRENT_DATE,
            'Тестовый орган $prefix',
            1
        FROM generate_series(1, $ROWS) AS i;
    "
    
    local duration_ms
    duration_ms=$(measure_time "$insert_sql")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo -e "  ${RED}✗ Ошибка при вставке данных${NC}" >&2
        echo "Ошибка: $duration_ms" >&2
        return 1
    fi
    
    count=$(docker_psql -c "SELECT COUNT(*) FROM app.student_documents WHERE student_id = $TEST_STUDENT_ID AND issuing_authority LIKE '%$prefix%';" | xargs)
    if [ "$count" != "$ROWS" ]; then
        echo -e "  ${RED}✗ Ожидалось $ROWS строк с префиксом '$prefix', вставлено $count. Тест прерван.${NC}" >&2
        return 1
    fi
    
    echo "$duration_ms"
}

# Чтение данных с префиксом
read_test_data() {
    local prefix=$1
    local select_sql="SELECT * FROM app.student_documents WHERE student_id = $TEST_STUDENT_ID AND issuing_authority LIKE '%$prefix%';"
    local duration_ms
    duration_ms=$(measure_time "$select_sql")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo -e "  ${RED}✗ Ошибка при чтении данных${NC}" >&2
        echo "Ошибка: $duration_ms" >&2
        return 1
    fi
    echo "$duration_ms"
}

# ============================================================================
# ОСНОВНОЙ ТЕСТ
# ============================================================================

echo -e "${YELLOW}====================================================${NC}"
echo -e "${YELLOW}  ТЕСТИРОВАНИЕ ПРОИЗВОДИТЕЛЬНОСТИ ШИФРОВАНИЯ${NC}"
echo -e "${YELLOW}====================================================${NC}\n"

prepare_test_student

# ----------------------------------------------------------------------------
# ТЕСТ 1: Вставка без шифрования
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}--- ТЕСТ 1: Вставка $ROWS строк без шифрования ---${NC}"
toggle_encryption "off"
time_off=$(insert_test_data "TEST_OFF" "off")
if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓ Время вставки без шифрования: ${time_off} мс${NC}"
else
    time_off="N/A"
fi
# Данные не удаляем

# ----------------------------------------------------------------------------
# ТЕСТ 2: Вставка с шифрованием
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}--- ТЕСТ 2: Вставка $ROWS строк с шифрованием ---${NC}"
toggle_encryption "on"
time_on=$(insert_test_data "TEST_ON" "on")
if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓ Время вставки с шифрованием: ${time_on} мс${NC}"
else
    time_on="N/A"
fi
# Данные не удаляем

# ----------------------------------------------------------------------------
# ТЕСТ 3: Чтение без SSL
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}--- ТЕСТ 3: Чтение $ROWS строк без SSL ---${NC}"
toggle_ssl "off"
# Убедимся, что шифрование включено
toggle_encryption "on"
# Вставляем данные для теста 3 (они останутся)
insert_test_data "TEST_SSL_OFF" "on" > /dev/null
if [ $? -ne 0 ]; then
    echo -e "  ${RED}✗ Не удалось вставить данные для теста SSL off${NC}"
    time_ssl_off="N/A"
else
    time_ssl_off=$(read_test_data "TEST_SSL_OFF")
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓ Время чтения без SSL: ${time_ssl_off} мс${NC}"
    else
        time_ssl_off="N/A"
    fi
fi

# ----------------------------------------------------------------------------
# ТЕСТ 4: Чтение с SSL
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}--- ТЕСТ 4: Чтение $ROWS строк с SSL ---${NC}"
toggle_ssl "on"
# Вставляем данные для теста 4
insert_test_data "TEST_SSL_ON" "on" > /dev/null
if [ $? -ne 0 ]; then
    echo -e "  ${RED}✗ Не удалось вставить данные для теста SSL on${NC}"
    time_ssl_on="N/A"
else
    time_ssl_on=$(read_test_data "TEST_SSL_ON")
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓ Время чтения с SSL: ${time_ssl_on} мс${NC}"
    else
        time_ssl_on="N/A"
    fi
fi

# ----------------------------------------------------------------------------
# РЕЗУЛЬТАТЫ
# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}--- РЕЗУЛЬТАТЫ ШИФРОВАНИЯ СТОЛБЦОВ ---${NC}"
echo -e "  ${BLUE}Вставка без шифрования:   ${time_off} мс"
echo -e "  ${BLUE}Вставка с шифрованием:    ${time_on} мс"
if [ "$time_off" != "N/A" ] && [ "$time_on" != "N/A" ]; then
    diff=$(echo "$time_on $time_off" | awk '{printf "%.3f", $1 - $2}')
    percent=$(echo "$time_on $time_off" | awk '{if ($2 != 0) printf "%.2f", 100 * ($1 - $2) / $2; else print "inf"}')
fi

echo -e "\n${YELLOW}--- РЕЗУЛЬТАТЫ SSL ---${NC}"
echo -e "  ${BLUE}Чтение без SSL:   ${time_ssl_off} мс"
echo -e "  ${BLUE}Чтение с SSL:     ${time_ssl_on} мс"
if [ "$time_ssl_off" != "N/A" ] && [ "$time_ssl_on" != "N/A" ]; then
    diff=$(echo "$time_ssl_on $time_ssl_off" | awk '{printf "%.3f", $1 - $2}')
    percent=$(echo "$time_ssl_on $time_ssl_off" | awk '{if ($2 != 0) printf "%.2f", 100 * ($1 - $2) / $2; else print "inf"}')
fi

# ----------------------------------------------------------------------------
# ОЧИСТКА ТЕСТОВЫХ ДАННЫХ
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}--- Очистка тестовых данных ---${NC}"
docker_psql -c "DELETE FROM app.student_documents WHERE student_id = $TEST_STUDENT_ID;" >/dev/null
echo -e "${GREEN}✓ Все тестовые документы удалены${NC}"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}  ТЕСТИРОВАНИЕ ЗАВЕРШЕНО${NC}"
echo -e "${GREEN}====================================================${NC}"