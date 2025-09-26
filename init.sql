--revoke
REVOKE ALL ON DATABASE education_db FROM PUBLIC;

CREATE ROLE test_connect WITH LOGIN;

--schemas
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS stg;

--roles
CREATE ROLE app_reader;
CREATE ROLE app_writer;
CREATE ROLE app_owner;
CREATE ROLE auditor;

CREATE ROLE ddl_admin;
CREATE ROLE dml_admin;
CREATE ROLE security_admin;

--privileges
-- ###### права для роли app_reader (только чтение)
GRANT CONNECT ON DATABASE education_db TO app_reader;
GRANT USAGE ON SCHEMA ref, app TO app_reader; --без справочников непонятно, что в бизнес-логике
ALTER DEFAULT PRIVILEGES IN SCHEMA ref GRANT SELECT ON TABLES TO app_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO app_reader;

-- ###### права для роли app_writer (чтение и запись в бизнес-логику)
GRANT CONNECT ON DATABASE education_db TO app_writer;
GRANT USAGE ON SCHEMA app TO app_writer;
GRANT USAGE ON SCHEMA ref TO app_writer; 
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE ON TABLES TO app_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref GRANT SELECT ON TABLES TO app_writer; --без справочников непонятно, что в бизнес-логике, однако запись необяз
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT USAGE ON SEQUENCES TO app_writer; -- без прав на автоинкремент не получится вставлять данные

-- ###### права для роли app_owner (полный доступ к данным приложения из предыдущих двух ролей + ddl)
GRANT CONNECT ON DATABASE education_db TO app_owner;
GRANT USAGE ON SCHEMA ref, app TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref, app GRANT ALL PRIVILEGES ON TABLES TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref, app GRANT ALL PRIVILEGES ON SEQUENCES TO app_owner; 

-- ###### права для роли auditor
GRANT CONNECT ON DATABASE education_db TO auditor;
GRANT USAGE ON SCHEMA audit TO auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT SELECT ON TABLES TO auditor;

-- ###### права для роли ddl_admin
GRANT CONNECT ON DATABASE education_db TO ddl_admin;
GRANT USAGE ON SCHEMA app, public, ref, stg, audit TO ddl_admin;
GRANT CREATE ON SCHEMA app, public, ref, stg, audit TO ddl_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE ddl_admin IN SCHEMA app, public, ref, stg, audit 
    GRANT REFERENCES, TRIGGER ON TABLES TO ddl_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE ddl_admin IN SCHEMA app, public, ref, stg, audit 
    GRANT USAGE ON SEQUENCES TO ddl_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE ddl_admin IN SCHEMA app, public, ref, stg, audit 
    GRANT EXECUTE ON FUNCTIONS TO ddl_admin;

-- ###### права для роли dml_admin
GRANT CONNECT ON DATABASE education_db TO dml_admin;
GRANT USAGE ON SCHEMA ref, app, stg TO dml_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref, app, stg 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dml_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref, app, stg 
    GRANT USAGE ON SEQUENCES TO dml_admin;
GRANT auditor TO dml_admin; -- для неповторяемости просмотра аудита

-- ###### права для роли security_admin
GRANT CONNECT ON DATABASE education_db TO security_admin;
GRANT USAGE ON SCHEMA app, ref, stg, audit TO security_admin WITH GRANT OPTION; -- права на использование схем и возможность делегирования этих прав
-- права на управление ролями и правами
ALTER ROLE security_admin CREATEROLE; -- создавать и удалять роли
GRANT auditor TO security_admin;
-- право просматривать системную информацию о ролях и привилегиях
GRANT SELECT ON pg_roles TO security_admin; -- видеть роли
GRANT SELECT ON pg_auth_members TO security_admin; -- видеть членство в ролях
-- право на информацию о таблицах, схемах и активных сеансах
GRANT SELECT ON pg_tables TO security_admin; -- все табл в БД
GRANT SELECT ON pg_namespace TO security_admin; -- инфа о схемах
GRANT SELECT ON pg_stat_activity TO security_admin; -- для просмотра активных сеансов
GRANT SELECT ON pg_locks TO security_admin; -- для анализа блокировок
-- дополнительные административные права
GRANT pg_read_all_settings TO security_admin; -- просмотр конфиги БД
GRANT pg_signal_backend TO security_admin; -- завершать сессии
GRANT pg_read_all_stats TO security_admin; -- просмотр всей статистики БД (производительность, использование индексов и т.д.)

-- Создание ENUM типов
CREATE TYPE academic_degree_enum AS ENUM ('Кандидат наук', 'Доктор наук', 'Нет');
CREATE TYPE academic_title_enum AS ENUM ('Доцент', 'Профессор', 'Нет');
CREATE TYPE student_status_enum AS ENUM ('Обучается', 'Академический отпуск', 'Отчислен', 'Выпустился');
CREATE TYPE control_type_enum AS ENUM ('Экзамен', 'Зачет');
CREATE TYPE day_of_week_enum AS ENUM ('Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота');
CREATE TYPE lesson_type_enum AS ENUM ('Лекция', 'Практика', 'Лабораторная');
CREATE TYPE document_type_enum AS ENUM ('Паспорт', 'Аттестат', 'Диплом', 'Мед. справка', 'ИНН', 'СНИЛС', 'Другое');

-- 1. Схема ref

-- 1.1. Учебные заведения
CREATE TABLE ref.educational_institutions (
    institution_id SERIAL PRIMARY KEY,
    institution_name VARCHAR(200) NOT NULL UNIQUE,
    short_name VARCHAR(20) NOT NULL,
    legal_address TEXT,
    rector_id INT -- FK добавлен после
);

-- 1.2. Факультеты/Институты
CREATE TABLE ref.faculties (
    faculty_id SERIAL PRIMARY KEY,
    faculty_name VARCHAR(100) NOT NULL,
    dean_id INT, -- FK добавлен после
    institution_id INT NOT NULL,
    FOREIGN KEY (institution_id) REFERENCES ref.educational_institutions(institution_id)
);

-- 1.3. Кафедры
CREATE TABLE ref.departments (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    head_of_department_id INT, -- FK добавлен после
    faculty_id INT NOT NULL,
    FOREIGN KEY (faculty_id) REFERENCES ref.faculties(faculty_id)
);

-- 1.4. Учебные группы
CREATE TABLE ref.study_groups (
    group_id SERIAL PRIMARY KEY,
    group_name VARCHAR(20) NOT NULL,
    admission_year INT NOT NULL DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    faculty_id INT NOT NULL,
    UNIQUE (group_name, admission_year),
    FOREIGN KEY (faculty_id) REFERENCES ref.faculties(faculty_id)
);

-- 1.5. Дисциплины
CREATE TABLE ref.subjects (
    subject_id SERIAL PRIMARY KEY,
    subject_name VARCHAR(100) NOT NULL,
    description TEXT
);

-- 1.6. Типы итоговых оценок
CREATE TABLE ref.final_grade_types (
    final_grade_type_id SERIAL PRIMARY KEY,
    grade_system_name VARCHAR(50) NOT NULL,
    allowed_values VARCHAR(255) NOT NULL
);

-- 2. Схема app

-- 2.1. Преподаватели
CREATE TABLE app.teachers (
    teacher_id SERIAL PRIMARY KEY,
    last_name VARCHAR(50) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    patronymic VARCHAR(50),
    academic_degree academic_degree_enum,
    academic_title academic_title_enum,
    email VARCHAR(255) UNIQUE,
    phone_number VARCHAR(20)
);

-- 2.2. Студенты
CREATE TABLE app.students (
    student_id SERIAL PRIMARY KEY,
    last_name VARCHAR(50) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    patronymic VARCHAR(50),
    student_card_number VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(255) UNIQUE,
    phone_number VARCHAR(20),
    group_id INT NOT NULL,
    status student_status_enum NOT NULL DEFAULT 'Обучается',
    FOREIGN KEY (group_id) REFERENCES ref.study_groups(group_id)
);

-- 2.3. Связь Преподаватель-Кафедра
CREATE TABLE app.teacher_departments (
    teacher_id INT NOT NULL,
    department_id INT NOT NULL,
    is_main BOOLEAN DEFAULT TRUE,
    position VARCHAR(100) NOT NULL,
    PRIMARY KEY (teacher_id, department_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id),
    FOREIGN KEY (department_id) REFERENCES ref.departments(department_id)
);

-- 2.4. Учебные планы
CREATE TABLE app.academic_plans (
    plan_id SERIAL PRIMARY KEY,
    group_id INT NOT NULL,
    subject_id INT NOT NULL,
    semester INT NOT NULL CHECK (semester > 0),
    total_hours INT NOT NULL,
    lecture_hours INT,
    practice_hours INT,
    control_type control_type_enum NOT NULL,
    UNIQUE (group_id, subject_id, semester),
    FOREIGN KEY (group_id) REFERENCES ref.study_groups(group_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id)
);

-- 2.5. Итоговые оценки
CREATE TABLE app.final_grades (
    final_grade_id SERIAL PRIMARY KEY,
    student_id INT NOT NULL,
    subject_id INT NOT NULL,
    teacher_id INT NOT NULL,
    final_grade_type_id INT NOT NULL,
    final_grade_value VARCHAR(10) NOT NULL,
    grade_date DATE NOT NULL DEFAULT CURRENT_DATE,
    semester INT NOT NULL,
    FOREIGN KEY (student_id) REFERENCES app.students(student_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id),
    FOREIGN KEY (final_grade_type_id) REFERENCES ref.final_grade_types(final_grade_type_id)
);

-- 2.6. Промежуточные оценки
CREATE TABLE app.interim_grades (
    interim_grade_id SERIAL PRIMARY KEY,
    student_id INT NOT NULL,
    subject_id INT NOT NULL,
    teacher_id INT NOT NULL,
    grade_value VARCHAR(10) NOT NULL,
    grade_date DATE NOT NULL DEFAULT CURRENT_DATE,
    grade_description VARCHAR(100),
    semester INT NOT NULL,
    FOREIGN KEY (student_id) REFERENCES app.students(student_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id)
);

-- 2.7. Расписание занятий
CREATE TABLE app.class_schedule (
    schedule_id SERIAL PRIMARY KEY,
    group_id INT NOT NULL,
    subject_id INT NOT NULL,
    teacher_id INT NOT NULL,
    week_number INT NOT NULL CHECK (week_number > 0 AND week_number < 8),
    day_of_week day_of_week_enum NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    classroom VARCHAR(20),
    building_number VARCHAR(10) NOT NULL,
    lesson_type lesson_type_enum NOT NULL,
    FOREIGN KEY (group_id) REFERENCES ref.study_groups(group_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id)
);

-- 2.8. Документы студентов
CREATE TABLE app.student_documents (
    document_id SERIAL PRIMARY KEY,
    student_id INT NOT NULL,
    document_type document_type_enum NOT NULL,
    document_series VARCHAR(20),
    document_number VARCHAR(50) NOT NULL,
    issue_date DATE,
    issuing_authority TEXT,
    FOREIGN KEY (student_id) REFERENCES app.students(student_id)
);

-- 3 Схема audit (Audit - аудит и логирование)

-- 3.1. Лог авторизаций
CREATE TABLE audit.login_log (
    log_id SERIAL PRIMARY KEY,
    login_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    username VARCHAR(100) NOT NULL,
    client_ip INET NOT NULL -- Тип INET для хранения IPv4 и IPv6 адресов
);

-- Добавление внешних ключей, которые ссылаются на таблицу teachers

-- Ректор учебного заведения
ALTER TABLE ref.educational_institutions 
ADD CONSTRAINT fk_institutions_rector 
FOREIGN KEY (rector_id) REFERENCES app.teachers(teacher_id);

-- Декан факультета
ALTER TABLE ref.faculties 
ADD CONSTRAINT fk_faculties_dean 
FOREIGN KEY (dean_id) REFERENCES app.teachers(teacher_id);

-- Заведующий кафедрой
ALTER TABLE ref.departments 
ADD CONSTRAINT fk_departments_head 
FOREIGN KEY (head_of_department_id) REFERENCES app.teachers(teacher_id);
