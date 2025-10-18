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
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref GRANT SELECT ON TABLES TO app_writer; --без справочников непонятно, что в бизнес-логике, однако запись необяз
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT USAGE ON SEQUENCES TO app_writer; -- без прав на автоинкремент не получится вставлять данные

-- ###### права для роли app_owner (полный доступ к данным приложения из предыдущих двух ролей + ddl)
GRANT CONNECT ON DATABASE education_db TO app_owner;
GRANT USAGE ON SCHEMA ref, app TO app_owner;
ALTER SCHEMA app OWNER TO app_owner;
GRANT ALL PRIVILEGES ON SCHEMA app TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL PRIVILEGES ON TABLES TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT TRIGGER ON TABLES TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL PRIVILEGES ON SEQUENCES TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL PRIVILEGES ON FUNCTIONS TO app_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref GRANT SELECT ON TABLES TO app_writer;

-- Права на создание объектов в схеме app
GRANT CREATE ON SCHEMA app TO app_owner;

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

-- ###### права для роли dml_admin
GRANT CONNECT ON DATABASE education_db TO dml_admin;
GRANT USAGE ON SCHEMA ref, app, stg TO dml_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref, app, stg 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dml_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref, app, stg 
    GRANT USAGE ON SEQUENCES TO dml_admin;

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

-- 1. Схема ref (остались только дисциплины и типы оценок)

-- 1.1. Дисциплины
CREATE TABLE ref.subjects (
    subject_id SERIAL PRIMARY KEY,
    subject_name VARCHAR(100) NOT NULL,
    description TEXT
);

-- 1.2. Типы итоговых оценок
CREATE TABLE ref.final_grade_types (
    final_grade_type_id SERIAL PRIMARY KEY,
    grade_system_name VARCHAR(50) NOT NULL,
    allowed_values VARCHAR(255) NOT NULL
);

-- 2. Схема app (все основные таблицы)

-- 2.1. Учебные заведения
CREATE TABLE app.educational_institutions (
    institution_id SERIAL PRIMARY KEY,
    institution_name VARCHAR(200) NOT NULL UNIQUE,
    short_name VARCHAR(20) NOT NULL,
    legal_address TEXT,
    rector_id INT -- FK добавлен после
);

-- 2.2. Факультеты/Институты
CREATE TABLE app.faculties (
    faculty_id SERIAL PRIMARY KEY,
    faculty_name VARCHAR(100) NOT NULL,
    dean_id INT, -- FK добавлен после
    institution_id INT NOT NULL,
    FOREIGN KEY (institution_id) REFERENCES app.educational_institutions(institution_id)
);

-- 2.3. Кафедры
CREATE TABLE app.departments (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    head_of_department_id INT, -- FK добавлен после
    faculty_id INT NOT NULL,
    FOREIGN KEY (faculty_id) REFERENCES app.faculties(faculty_id)
);

-- 2.4. Учебные группы
CREATE TABLE app.study_groups (
    group_id SERIAL PRIMARY KEY,
    group_name VARCHAR(20) NOT NULL,
    admission_year INT NOT NULL DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    faculty_id INT NOT NULL,
    UNIQUE (group_name, admission_year),
    FOREIGN KEY (faculty_id) REFERENCES app.faculties(faculty_id)
);

-- 2.5. Преподаватели
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

-- 2.6. Студенты
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
    FOREIGN KEY (group_id) REFERENCES app.study_groups(group_id)
);

-- 2.7. Связь Преподаватель-Кафедра
CREATE TABLE app.teacher_departments (
    teacher_id INT NOT NULL,
    department_id INT NOT NULL,
    is_main BOOLEAN DEFAULT TRUE,
    position VARCHAR(100) NOT NULL,
    PRIMARY KEY (teacher_id, department_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id),
    FOREIGN KEY (department_id) REFERENCES app.departments(department_id)
);

-- 2.8. Учебные планы
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
    FOREIGN KEY (group_id) REFERENCES app.study_groups(group_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id)
);

-- 2.9. Итоговые оценки
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

-- 2.10. Промежуточные оценки
CREATE TABLE app.interim_grades (
    interim_grade_id SERIAL PRIMARY KEY,
    student_id INT NOT NULL,
    subject_id INT NOT NULL,
    teacher_id INT NOT NULL,
    grade_value VARCHAR(5) NOT NULL,
    grade_date DATE NOT NULL DEFAULT CURRENT_DATE,
    grade_description VARCHAR(100),
    semester INT NOT NULL,
    FOREIGN KEY (student_id) REFERENCES app.students(student_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id)
);

-- 2.11. Расписание занятий
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
    FOREIGN KEY (group_id) REFERENCES app.study_groups(group_id),
    FOREIGN KEY (subject_id) REFERENCES ref.subjects(subject_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id)
);

-- 2.12. Документы студентов
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

--3.2 Лог вызова функций
CREATE TABLE audit.function_calls (
    call_id SERIAL PRIMARY KEY,
    call_time TIMESTAMP NOT NULL DEFAULT NOW(),
    function_name VARCHAR(100) NOT NULL,
    caller_role VARCHAR(100) NOT NULL,
    input_params JSONB,
    success BOOLEAN NOT NULL
);

-- Добавление внешних ключей, которые ссылаются на таблицу teachers

-- Ректор учебного заведения
ALTER TABLE app.educational_institutions 
ADD CONSTRAINT fk_institutions_rector 
FOREIGN KEY (rector_id) REFERENCES app.teachers(teacher_id);

-- Декан факультета
ALTER TABLE app.faculties 
ADD CONSTRAINT fk_faculties_dean 
FOREIGN KEY (dean_id) REFERENCES app.teachers(teacher_id);

-- Заведующий кафедрой
ALTER TABLE app.departments 
ADD CONSTRAINT fk_departments_head 
FOREIGN KEY (head_of_department_id) REFERENCES app.teachers(teacher_id);


--indexes
-- индексы для внешних ключей
CREATE INDEX idx_students_group_id ON app.students(group_id);
CREATE INDEX idx_academic_plans_group_id ON app.academic_plans(group_id);
CREATE INDEX idx_academic_plans_subject_id ON app.academic_plans(subject_id);
CREATE INDEX idx_final_grades_student_id ON app.final_grades(student_id);
CREATE INDEX idx_interim_grades_student_id ON app.interim_grades(student_id);

-- индексы для основных сценариев
-- расписание группы на неделю
CREATE INDEX idx_class_schedule_group_week_day ON app.class_schedule(group_id, week_number, day_of_week);

-- оценки студента за семестр
CREATE INDEX idx_final_grades_student_semester ON app.final_grades(student_id, semester);

-- поиск студентов/преподавателей по ФИО
CREATE INDEX idx_students_name ON app.students(last_name, first_name);
CREATE INDEX idx_teachers_name ON app.teachers(last_name, first_name);


-- 1. Добавляем таблицу сегментов в схему ref
CREATE TABLE ref.segments (
    segment_id SERIAL PRIMARY KEY,
    segment_name VARCHAR(200) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Добавляем segment_id в ключевые таблицы app.*

-- 2.1. Учебные заведения (основная таблица сегментов)
ALTER TABLE app.educational_institutions ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.educational_institutions 
ADD CONSTRAINT fk_institutions_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.2. Факультеты/Институты
ALTER TABLE app.faculties ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.faculties 
ADD CONSTRAINT fk_faculties_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.3. Кафедры
ALTER TABLE app.departments ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.departments 
ADD CONSTRAINT fk_departments_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.4. Учебные группы
ALTER TABLE app.study_groups ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.study_groups 
ADD CONSTRAINT fk_groups_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.5. Преподаватели (основная таблица)
ALTER TABLE app.teachers ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.teachers 
ADD CONSTRAINT fk_teachers_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.6. Студенты (основная таблица)
ALTER TABLE app.students ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.students 
ADD CONSTRAINT fk_students_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.7. Учебные планы
ALTER TABLE app.academic_plans ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.academic_plans 
ADD CONSTRAINT fk_plans_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.8. Итоговые оценки
ALTER TABLE app.final_grades ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.final_grades 
ADD CONSTRAINT fk_final_grades_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.9. Промежуточные оценки
ALTER TABLE app.interim_grades ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.interim_grades 
ADD CONSTRAINT fk_interim_grades_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.10. Расписание занятий
ALTER TABLE app.class_schedule ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.class_schedule 
ADD CONSTRAINT fk_schedule_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 2.11. Документы студентов
ALTER TABLE app.student_documents ADD COLUMN segment_id INT NOT NULL;
ALTER TABLE app.student_documents 
ADD CONSTRAINT fk_documents_segment 
FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);

-- 3. Таблицы-связки для студентов и преподавателей (многие-ко-многим)

-- 3.1. Связь Студент-УчебноеЗаведение (для студентов, которые учатся в нескольких вузах)
CREATE TABLE app.student_institutions (
    student_id INT NOT NULL,
    institution_id INT NOT NULL,
    segment_id INT NOT NULL,
    enrollment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status student_status_enum NOT NULL DEFAULT 'Обучается',
    PRIMARY KEY (student_id, institution_id, segment_id),
    FOREIGN KEY (student_id) REFERENCES app.students(student_id),
    FOREIGN KEY (institution_id) REFERENCES app.educational_institutions(institution_id),
    FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id)
);

-- 3.2. Связь Преподаватель-УчебноеЗаведение (для преподавателей, работающих в нескольких вузах)
CREATE TABLE app.teacher_institutions (
    teacher_id INT NOT NULL,
    institution_id INT NOT NULL,
    segment_id INT NOT NULL,
    employment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    position VARCHAR(100) NOT NULL,
    is_main_workplace BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (teacher_id, institution_id, segment_id),
    FOREIGN KEY (teacher_id) REFERENCES app.teachers(teacher_id),
    FOREIGN KEY (institution_id) REFERENCES app.educational_institutions(institution_id),
    FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id)
);

-- 4. Индексы для условий политик (segment_id + ключи фильтрации)

-- Основные индексы по segment_id
CREATE INDEX idx_educational_institutions_segment ON app.educational_institutions(segment_id);
CREATE INDEX idx_faculties_segment ON app.faculties(segment_id);
CREATE INDEX idx_departments_segment ON app.departments(segment_id);
CREATE INDEX idx_study_groups_segment ON app.study_groups(segment_id);
CREATE INDEX idx_teachers_segment ON app.teachers(segment_id);
CREATE INDEX idx_students_segment ON app.students(segment_id);
CREATE INDEX idx_academic_plans_segment ON app.academic_plans(segment_id);
CREATE INDEX idx_final_grades_segment ON app.final_grades(segment_id);
CREATE INDEX idx_interim_grades_segment ON app.interim_grades(segment_id);
CREATE INDEX idx_class_schedule_segment ON app.class_schedule(segment_id);
CREATE INDEX idx_student_documents_segment ON app.student_documents(segment_id);
CREATE INDEX idx_student_institutions_segment ON app.student_institutions(segment_id);
CREATE INDEX idx_teacher_institutions_segment ON app.teacher_institutions(segment_id);

-- Комбинированные индексы для частых запросов
CREATE INDEX idx_students_segment_group ON app.students(segment_id, group_id);
CREATE INDEX idx_grades_student_segment_semester ON app.final_grades(segment_id, student_id, semester);
CREATE INDEX idx_grades_subject_segment ON app.final_grades(segment_id, subject_id);
CREATE INDEX idx_schedule_group_segment_week ON app.class_schedule(segment_id, group_id, week_number);
CREATE INDEX idx_plans_group_segment ON app.academic_plans(segment_id, group_id);

-- ОБНОВЛЕННОЕ ЗАПОЛНЕНИЕ ТЕСТОВЫХ ДАННЫХ С СЕГМЕНТАЦИЕЙ

-- 1. Сначала заполняем segments
INSERT INTO ref.segments (segment_id, segment_name, description) VALUES
(1, 'НИУ ВШЭ - Москва', 'Национальный исследовательский университет "Высшая школа экономики" - Московский кампус'),
(2, 'НИУ ВШЭ - СПб', 'Национальный исследовательский университет "Высшая школа экономики" - Санкт-Петербургский кампус'),
(3, 'НИУ ВШЭ - Нижний Новгород', 'Национальный исследовательский университет "Высшая школа экономики" - Нижегородский кампус'),
(4, 'МГУ', 'Московский государственный университет имени М.В. Ломоносова'),
(5, 'МФТИ', 'Московский физико-технический институт'),
(6, 'РУДН', 'Российский университет дружбы народов'),
(7, 'НГТУ', 'Новосибирский государственный технический университет');

-- 2. Заполняем справочники (они не зависят от других таблиц)
INSERT INTO ref.subjects (subject_id, subject_name, description) VALUES
(1, 'Математический анализ', 'Дифференциальное и интегральное исчисление'),
(2, 'Линейная алгебра', 'Векторные пространства, матрицы, системы линейных уравнений'),
(3, 'Программирование на Python', 'Основы программирования на языке Python'),
(4, 'Базы данных', 'Проектирование и работа с реляционными базами данных'),
(5, 'Теория вероятностей', 'Вероятностные модели и статистические методы'),
(6, 'Экономика', 'Основы микро- и макроэкономики'),
(7, 'Физика', 'Механика, термодинамика, электромагнетизм'),
(8, 'Алгоритмы и структуры данных', 'Анализ алгоритмов, основные структуры данных'),
(9, 'Машинное обучение', 'Методы и алгоритмы машинного обучения'),
(10, 'Веб-разработка', 'Создание веб-приложений');

INSERT INTO ref.final_grade_types (final_grade_type_id, grade_system_name, allowed_values) VALUES
(1, '5-балльная система', '2,3,4,5'),
(2, 'Зачет/Незачет', 'Зачет,Незачет'),
(3, '100-балльная система', '0-100'),
(4, 'Буквенная система', 'A,B,C,D,E,F'),
(5, '10-балльная система', '1-10');

-- 3. Затем заполняем teachers (они нужны для rector_id)
INSERT INTO app.teachers (teacher_id, last_name, first_name, patronymic, academic_degree, academic_title, email, phone_number, segment_id) VALUES
-- НИУ ВШЭ - Москва (segment_id = 1)
(1, 'Иванов', 'Петр', 'Сергеевич', 'Доктор наук', 'Профессор', 'ivanov@hse.ru', '+7-900-123-45-67', 1),
(2, 'Петрова', 'Мария', 'Ивановна', 'Кандидат наук', 'Доцент', 'petrova@hse.ru', '+7-900-123-45-68', 1),
-- НИУ ВШЭ - СПб (segment_id = 2)
(3, 'Сидоров', 'Алексей', 'Владимирович', 'Кандидат наук', 'Доцент', 'sidorov@hse.spb.ru', '+7-900-123-45-69', 2),
(4, 'Кузнецова', 'Елена', 'Анатольевна', 'Доктор наук', 'Профессор', 'kuznetsova@hse.spb.ru', '+7-900-123-45-70', 2),
-- НИУ ВШЭ - НН (segment_id = 3)
(5, 'Смирнов', 'Дмитрий', 'Петрович', 'Кандидат наук', 'Доцент', 'smirnov@hse.nn.ru', '+7-900-123-45-71', 3),
(6, 'Федорова', 'Ольга', 'Викторовна', 'Нет', 'Доцент', 'fedorova@hse.nn.ru', '+7-900-123-45-72', 3),
-- МГУ (segment_id = 4)
(7, 'Батаев', 'Анатолий', 'Андреевич', 'Доктор наук', 'Профессор', 'rector@msu.ru', '+7-383-346-08-43', 4),
(8, 'Васильева', 'Анна', 'Сергеевна', 'Нет', 'Доцент', 'vasilyeva@msu.ru', '+7-900-123-45-74', 4),
-- МФТИ (segment_id = 5)
(9, 'Алексеев', 'Игорь', 'Валентинович', 'Доктор наук', 'Профессор', 'alekseev@phystech.ru', '+7-900-123-45-75', 5),
(10, 'Николаева', 'Татьяна', 'Борисовна', 'Кандидат наук', 'Доцент', 'nikolaeva@phystech.ru', '+7-900-123-45-76', 5),
-- РУДН (segment_id = 6)
(11, 'Орлов', 'Сергей', 'Михайлович', 'Доктор наук', 'Профессор', 'orlov@rudn.ru', '+7-900-123-45-77', 6),
(12, 'Жукова', 'Лариса', 'Викторовна', 'Кандидат наук', 'Доцент', 'zhukova@rudn.ru', '+7-900-123-45-78', 6),
-- НГТУ (segment_id = 7)
(13, 'Ковалев', 'Андрей', 'Николаевич', 'Доктор наук', 'Профессор', 'kovalev@nstu.ru', '+7-900-123-45-79', 7),
(14, 'Григорьева', 'Наталья', 'Олеговна', 'Кандидат наук', 'Доцент', 'grigorieva@nstu.ru', '+7-900-123-45-80', 7);

-- 4. Теперь заполняем educational_institutions (они используют teacher_id как rector_id)
INSERT INTO app.educational_institutions (institution_id, institution_name, short_name, legal_address, rector_id, segment_id) VALUES
(1, 'НИУ ВШЭ - Москва', 'НИУ ВШЭ', 'г. Москва, ул. Мясницкая, д. 20', 1, 1),
(2, 'НИУ ВШЭ - Санкт-Петербург', 'НИУ ВШЭ СПб', 'г. Санкт-Петербург, ул. Кантемировская, д. 3', 3, 2),
(3, 'НИУ ВШЭ - Нижний Новгород', 'НИУ ВШЭ НН', 'г. Нижний Новгород, ул. Б. Печерская, д. 25', 5, 3),
(4, 'МГУ имени М.В. Ломоносова', 'МГУ', 'г. Москва, Ленинские горы, д. 1', 7, 4),
(5, 'Московский физико-технический институт', 'МФТИ', 'г. Москва, ул. Климентовский пер, д. 1', 9, 5),
(6, 'Российский университет дружбы народов', 'РУДН', 'г. Москва, ул. Миклухо-Маклая, д. 6', 11, 6),
(7, 'Новосибирский государственный технический университет', 'НГТУ', 'г. Новосибирск, пр-т К.Маркса, д. 20', 13, 7);

-- 5. Затем faculties
INSERT INTO app.faculties (faculty_id, faculty_name, dean_id, institution_id, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 'Факультет компьютерных наук', 1, 1, 1),
(2, 'Экономический факультет', 2, 1, 1),
-- НИУ ВШЭ - СПб
(3, 'Факультет Санкт-Петербургская школа экономики и менеджмента', 3, 2, 2),
(4, 'Юридический факультет', 4, 2, 2),
-- НИУ ВШЭ - НН
(5, 'Факультет информатики, математики и компьютерных наук', 5, 3, 3),
(6, 'Факультет гуманитарных наук', 6, 3, 3),
-- МГУ
(7, 'Механико-математический факультет', 7, 4, 4),
(8, 'Факультет вычислительной математики и кибернетики', 8, 4, 4),
-- МФТИ
(9, 'Факультет общей и прикладной физики', 9, 5, 5),
(10, 'Факультет радиотехники и кибернетики', 10, 5, 5),
-- РУДН
(11, 'Инженерный факультет', 11, 6, 6),
(12, 'Экономический факультет', 12, 6, 6),
-- НГТУ
(13, 'Факультет радиотехники и электроники', 13, 7, 7),
(14, 'Факультет прикладной математики', 14, 7, 7);

-- 6. Затем departments
INSERT INTO app.departments (department_id, department_name, head_of_department_id, faculty_id, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 'Кафедра программной инженерии', 1, 1, 1),
(2, 'Кафедра анализа данных', 2, 1, 1),
-- НИУ ВШЭ - СПб
(3, 'Кафедра экономической теории', 3, 3, 2),
(4, 'Кафедра менеджмента', 4, 3, 2),
-- НИУ ВШЭ - НН
(5, 'Кафедра информатики', 5, 5, 3),
(6, 'Кафедра математики', 6, 5, 3),
-- МГУ
(7, 'Кафедра высшей математики', 7, 7, 4),
(8, 'Кафедра дифференциальных уравнений', 8, 7, 4),
-- МФТИ
(9, 'Кафедра теоретической физики', 9, 9, 5),
(10, 'Кафедра квантовой электроники', 10, 9, 5),
-- РУДН
(11, 'Кафедра системного анализа', 11, 11, 6),
(12, 'Кафедра электротехники', 12, 11, 6),
-- НГТУ
(13, 'Кафедра радиотехнических систем', 13, 13, 7),
(14, 'Кафедра вычислительной математики', 14, 14, 7);

-- 7. Затем study_groups
INSERT INTO app.study_groups (group_id, group_name, admission_year, faculty_id, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 'БПИ2301', 2023, 1, 1),
(2, 'БЭК2301', 2023, 2, 1),
-- НИУ ВШЭ - СПб
(3, 'БМ2301', 2023, 3, 2),
(4, 'БЮ2301', 2023, 4, 2),
-- НИУ ВШЭ - НН
(5, 'БИ2301', 2023, 5, 3),
(6, 'БГН2301', 2023, 6, 3),
-- МГУ
(7, 'ММ2301', 2023, 7, 4),
(8, 'ВМК2301', 2023, 8, 4),
-- МФТИ
(9, 'ФФ2301', 2023, 9, 5),
(10, 'РК2301', 2023, 10, 5),
-- РУДН
(11, 'ИФ2301', 2023, 11, 6),
(12, 'ЭФ2301', 2023, 12, 6),
-- НГТУ
(13, 'РЭ2301', 2023, 13, 7),
(14, 'ПМ2301', 2023, 14, 7);

-- 8. Затем students
INSERT INTO app.students (student_id, last_name, first_name, patronymic, student_card_number, email, phone_number, group_id, status, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 'Соколов', 'Александр', 'Игоревич', 'ВШЭ-М-2023-001', 'sokolov@edu.hse.ru', '+7-900-200-01-01', 1, 'Обучается', 1),
(2, 'Орлова', 'Виктория', 'Сергеевна', 'ВШЭ-М-2023-002', 'orlova@edu.hse.ru', '+7-900-200-01-02', 1, 'Обучается', 1),
-- НИУ ВШЭ - СПб
(3, 'Лебедев', 'Максим', 'Александрович', 'ВШЭ-СПб-2023-001', 'lebedev@edu.hse.spb.ru', '+7-900-200-01-03', 3, 'Обучается', 2),
(4, 'Егорова', 'Анастасия', 'Дмитриевна', 'ВШЭ-СПб-2023-002', 'egorova@edu.hse.spb.ru', '+7-900-200-01-04', 3, 'Академический отпуск', 2),
-- НИУ ВШЭ - НН
(5, 'Козлов', 'Артем', 'Витальевич', 'ВШЭ-НН-2023-001', 'kozlov@edu.hse.nn.ru', '+7-900-200-01-05', 5, 'Обучается', 3),
(6, 'Новикова', 'Екатерина', 'Андреевна', 'ВШЭ-НН-2023-002', 'novikova@edu.hse.nn.ru', '+7-900-200-01-06', 5, 'Обучается', 3),
-- МГУ
(7, 'Морозов', 'Иван', 'Олегович', 'МГУ-2023-001', 'morozov@edu.msu.ru', '+7-900-200-01-07', 7, 'Отчислен', 4),
(8, 'Павлова', 'София', 'Романовна', 'МГУ-2023-002', 'pavlova@edu.msu.ru', '+7-900-200-01-08', 7, 'Обучается', 4),
-- МФТИ
(9, 'Волков', 'Кирилл', 'Иванович', 'МФТИ-2023-001', 'volkov@edu.phystech.ru', '+7-900-200-01-09', 9, 'Обучается', 5),
(10, 'Андреева', 'Дарья', 'Викторовна', 'МФТИ-2023-002', 'andreeva@edu.phystech.ru', '+7-900-200-01-10', 9, 'Выпустился', 5),
-- РУДН
(11, 'Петров', 'Дмитрий', 'Сергеевич', 'РУДН-2023-001', 'petrov@edu.rudn.ru', '+7-900-200-01-11', 11, 'Обучается', 6),
(12, 'Сидорова', 'Мария', 'Алексеевна', 'РУДН-2023-002', 'sidorova@edu.rudn.ru', '+7-900-200-01-12', 11, 'Обучается', 6),
-- НГТУ
(13, 'Кузнецов', 'Алексей', 'Владимирович', 'НГТУ-2023-001', 'kuznetsov@edu.nstu.ru', '+7-900-200-01-13', 13, 'Обучается', 7),
(14, 'Иванова', 'Анна', 'Петровна', 'НГТУ-2023-002', 'ivanova@edu.nstu.ru', '+7-900-200-01-14', 13, 'Обучается', 7);

-- 9. Теперь academic_plans (после всех зависимостей)
INSERT INTO app.academic_plans (group_id, subject_id, semester, total_hours, lecture_hours, practice_hours, control_type, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 1, 1, 144, 72, 72, 'Экзамен', 1),
(1, 2, 1, 108, 54, 54, 'Зачет', 1),
-- НИУ ВШЭ - СПб
(3, 3, 1, 144, 72, 72, 'Экзамен', 2),
(3, 4, 1, 90, 45, 45, 'Зачет', 2),
-- НИУ ВШЭ - НН
(5, 5, 2, 120, 60, 60, 'Экзамен', 3),
(5, 6, 2, 96, 48, 48, 'Зачет', 3),
-- МГУ
(7, 7, 2, 132, 66, 66, 'Экзамен', 4),
(7, 8, 2, 84, 42, 42, 'Зачет', 4),
-- МФТИ
(9, 9, 3, 156, 78, 78, 'Экзамен', 5),
(9, 10, 3, 102, 51, 51, 'Зачет', 5),
-- РУДН
(11, 1, 1, 144, 72, 72, 'Экзамен', 6),
(11, 3, 1, 108, 54, 54, 'Зачет', 6),
-- НГТУ
(13, 2, 1, 120, 60, 60, 'Экзамен', 7),
(13, 4, 1, 96, 48, 48, 'Зачет', 7);

-- 10. teacher_departments (после teachers и departments)
INSERT INTO app.teacher_departments (teacher_id, department_id, is_main, position) VALUES
-- НИУ ВШЭ - Москва
(1, 1, true, 'Профессор'),
(2, 2, true, 'Доцент'),
-- НИУ ВШЭ - СПб
(3, 3, true, 'Доцент'),
(4, 4, true, 'Профессор'),
-- НИУ ВШЭ - НН
(5, 5, true, 'Доцент'),
(6, 6, true, 'Старший преподаватель'),
-- МГУ
(7, 7, true, 'Профессор'),
(8, 8, true, 'Доцент'),
-- МФТИ
(9, 9, true, 'Профессор'),
(10, 10, true, 'Доцент'),
-- РУДН
(11, 11, true, 'Профессор'),
(12, 12, true, 'Доцент'),
-- НГТУ
(13, 13, true, 'Профессор'),
(14, 14, true, 'Доцент');

-- 11. final_grades (после students, subjects, teachers, final_grade_types)
INSERT INTO app.final_grades (student_id, subject_id, teacher_id, final_grade_type_id, final_grade_value, grade_date, semester, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 1, 1, 1, '5', '2024-01-20', 1, 1),
(2, 1, 1, 1, '4', '2024-01-20', 1, 1),
-- НИУ ВШЭ - СПб
(3, 3, 3, 1, '5', '2024-01-21', 1, 2),
(4, 4, 4, 1, '3', '2024-01-22', 1, 2),
-- НИУ ВШЭ - НН
(5, 5, 5, 1, '4', '2024-06-15', 2, 3),
(6, 6, 6, 1, '5', '2024-06-16', 2, 3),
-- МГУ
(7, 7, 7, 1, '2', '2024-06-17', 2, 4),
(8, 8, 8, 1, '4', '2024-06-18', 2, 4),
-- МФТИ
(9, 9, 9, 1, '5', '2024-12-20', 3, 5),
(10, 10, 10, 1, '3', '2024-12-21', 3, 5),
-- РУДН
(11, 1, 11, 1, '4', '2024-01-25', 1, 6),
(12, 3, 12, 1, '5', '2024-01-26', 1, 6),
-- НГТУ
(13, 2, 13, 1, '4', '2024-01-27', 1, 7),
(14, 4, 14, 1, '5', '2024-01-28', 1, 7);

-- 12. interim_grades (после students, subjects, teachers)
INSERT INTO app.interim_grades (student_id, subject_id, teacher_id, grade_value, grade_date, grade_description, semester, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 1, 1, '5', '2023-10-15', 'Контрольная работа 1', 1, 1),
(1, 1, 1, '4', '2023-11-20', 'Контрольная работа 2', 1, 1),
(2, 1, 1, '4', '2023-10-15', 'Контрольная работа 1', 1, 1),
-- НИУ ВШЭ - СПб
(3, 3, 3, '5', '2023-10-16', 'Контрольная работа 1', 1, 2),
(4, 4, 4, '4', '2023-11-18', 'Лабораторная работа', 1, 2),
-- НИУ ВШЭ - НН
(5, 5, 5, '4', '2024-03-10', 'Лабораторная работа', 2, 3),
(6, 6, 6, '5', '2024-03-12', 'Практическое задание', 2, 3),
(5, 5, 5, '5', '2024-04-15', 'Контрольная работа', 2, 3),
-- МГУ
(8, 8, 8, '3', '2024-03-15', 'Тестирование', 2, 4),
(8, 7, 7, '4', '2024-04-20', 'Семинар', 2, 4),
-- МФТИ
(9, 9, 9, '5', '2024-09-20', 'Курсовая работа', 3, 5),
(9, 9, 9, '4', '2024-10-25', 'Проект', 3, 5),
(10, 10, 10, '3', '2024-09-22', 'Семинар', 3, 5),
-- РУДН
(11, 1, 11, '4', '2023-10-18', 'Семинар', 1, 6),
(12, 3, 12, '5', '2023-11-25', 'Практическая работа', 1, 6),
-- НГТУ
(13, 2, 13, '5', '2023-10-19', 'Лабораторная работа', 1, 7),
(14, 4, 14, '4', '2023-11-22', 'Контрольная работа', 1, 7),
(13, 2, 13, '4', '2023-12-10', 'Тестирование', 1, 7);

-- 13. class_schedule (после groups, subjects, teachers)
INSERT INTO app.class_schedule (group_id, subject_id, teacher_id, week_number, day_of_week, start_time, end_time, classroom, building_number, lesson_type, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 1, 1, 1, 'Понедельник', '09:00', '10:30', '101', '1', 'Лекция', 1),
(1, 2, 1, 1, 'Среда', '10:40', '12:10', '201', '1', 'Практика', 1),
(2, 1, 2, 1, 'Вторник', '09:00', '10:30', '102', '1', 'Лекция', 1),
-- НИУ ВШЭ - СПб
(3, 3, 3, 1, 'Вторник', '09:00', '10:30', '102', '1', 'Лекция', 2),
(3, 4, 4, 1, 'Четверг', '13:30', '15:00', '301', '2', 'Лабораторная', 2),
(4, 3, 3, 1, 'Пятница', '11:00', '12:30', '202', '1', 'Практика', 2),
-- НИУ ВШЭ - НН
(5, 5, 5, 2, 'Понедельник', '15:10', '16:40', '401', '3', 'Лекция', 3),
(5, 6, 6, 2, 'Пятница', '12:20', '13:50', '501', '3', 'Практика', 3),
(6, 5, 5, 2, 'Среда', '14:00', '15:30', '402', '3', 'Лекция', 3),
-- МГУ
(7, 7, 7, 2, 'Среда', '16:50', '18:20', '601', '4', 'Лабораторная', 4),
(7, 8, 8, 2, 'Суббота', '10:40', '12:10', '701', '4', 'Лекция', 4),
(8, 7, 7, 2, 'Четверг', '13:00', '14:30', '602', '4', 'Практика', 4),
-- МФТИ
(9, 9, 9, 3, 'Вторник', '13:30', '15:00', '801', '5', 'Практика', 5),
(9, 10, 10, 3, 'Четверг', '15:10', '16:40', '901', '5', 'Лабораторная', 5),
(10, 9, 9, 3, 'Понедельник', '11:00', '12:30', '802', '5', 'Лекция', 5),
-- РУДН
(11, 1, 11, 1, 'Понедельник', '11:00', '12:30', '105', '1', 'Лекция', 6),
(11, 3, 12, 1, 'Среда', '14:00', '15:30', '205', '1', 'Практика', 6),
(12, 1, 11, 1, 'Вторник', '09:00', '10:30', '106', '1', 'Лекция', 6),
-- НГТУ
(13, 2, 13, 1, 'Вторник', '10:00', '11:30', '110', '2', 'Лекция', 7),
(13, 4, 14, 1, 'Четверг', '16:00', '17:30', '210', '2', 'Лабораторная', 7),
(14, 2, 13, 1, 'Пятница', '13:00', '14:30', '111', '2', 'Практика', 7);

-- 14. student_documents (после students)
INSERT INTO app.student_documents (student_id, document_type, document_series, document_number, issue_date, issuing_authority, segment_id) VALUES
-- НИУ ВШЭ - Москва
(1, 'Паспорт', '4501', '123456', '2018-04-15', 'ОУФМС России по г. Москве', 1),
(1, 'Аттестат', NULL, '789-123', '2022-06-25', 'Гимназия №1 г. Москвы', 1),
(2, 'Паспорт', '4502', '234567', '2019-05-20', 'ОУФМС России по г. Москве', 1),
(2, 'Аттестат', NULL, '789-124', '2022-06-25', 'Лицей №2 г. Москвы', 1),
-- НИУ ВШЭ - СПб
(3, 'Паспорт', '4503', '345678', '2020-03-10', 'ОУФМС России по г. Санкт-Петербургу', 2),
(3, 'Аттестат', NULL, '789-125', '2022-06-25', 'Лицей №2 г. Санкт-Петербурга', 2),
(3, 'Мед. справка', NULL, '086У-2023', '2023-08-15', 'Поликлиника №1 г. Санкт-Петербург', 2),
-- НИУ ВШЭ - НН
(4, 'Паспорт', '4504', '456789', '2018-07-12', 'ОУФМС России по г. Нижнему Новгороду', 3),
(4, 'ИНН', NULL, '1234567890', '2023-09-01', 'ИФНС России по г. Нижнему Новгороду', 3),
(5, 'Паспорт', '4505', '567890', '2019-11-05', 'ОУФМС России по г. Нижнему Новгороду', 3),
(5, 'СНИЛС', NULL, '123-456-789-01', '2023-09-01', 'ПФР по г. Нижнему Новгороду', 3),
-- МГУ
(6, 'Паспорт', '4506', '678901', '2018-09-20', 'ОУФМС России по г. Москве', 4),
(6, 'Аттестат', NULL, '789-126', '2022-06-25', 'Школа №3 г. Москвы', 4),
(7, 'Паспорт', '4507', '789012', '2019-02-14', 'ОУФМС России по г. Москве', 4),
(7, 'Мед. справка', NULL, '086У-2024', '2023-08-20', 'Поликлиника №2 г. Москва', 4),
-- МФТИ
(8, 'Паспорт', '4508', '890123', '2020-06-30', 'ОУФМС России по г. Москве', 5),
(8, 'Аттестат', NULL, '789-127', '2022-06-25', 'Лицей №5 г. Москвы', 5),
(9, 'Паспорт', '4509', '901234', '2019-08-25', 'ОУФМС России по г. Москве', 5),
(9, 'ИНН', NULL, '2345678901', '2023-09-01', 'ИФНС России по г. Москве', 5),
-- РУДН
(10, 'Паспорт', '4510', '012345', '2018-12-10', 'ОУФМС России по г. Москве', 6),
(10, 'СНИЛС', NULL, '234-567-890-12', '2023-09-01', 'ПФР по г. Москве', 6),
(11, 'Паспорт', '4511', '123456', '2019-04-18', 'ОУФМС России по г. Москве', 6),
(11, 'Аттестат', NULL, '789-128', '2022-06-25', 'Гимназия №7 г. Москвы', 6),
-- НГТУ
(12, 'Паспорт', '4512', '234567', '2020-01-22', 'ОУФМС России по г. Новосибирску', 7),
(12, 'Мед. справка', NULL, '086У-2025', '2023-08-25', 'Поликлиника №3 г. Новосибирск', 7),
(13, 'Паспорт', '4513', '345678', '2019-07-08', 'ОУФМС России по г. Новосибирску', 7),
(13, 'Аттестат', NULL, '789-129', '2022-06-25', 'Лицей №1 г. Новосибирска', 7),
(14, 'Паспорт', '4514', '456789', '2018-10-15', 'ОУФМС России по г. Новосибирску', 7),
(14, 'ИНН', NULL, '3456789012', '2023-09-01', 'ИФНС России по г. Новосибирску', 7);

-- 15. Таблицы-связки для многих-ко-многим (после всех основных таблиц)

-- Студенты, которые учатся в нескольких вузах (пример)
INSERT INTO app.student_institutions (student_id, institution_id, segment_id, enrollment_date, status) VALUES
(1, 1, 1, '2023-09-01', 'Обучается'),  -- Соколов в ВШЭ Москва (основное)
(1, 4, 4, '2023-09-01', 'Обучается'),  -- Соколов также в МГУ (совмещает)
(3, 2, 2, '2023-09-01', 'Обучается'),  -- Лебедев в ВШЭ СПб (основное)
(3, 6, 6, '2023-09-01', 'Обучается'),  -- Лебедев также в РУДН
(5, 3, 3, '2023-09-01', 'Обучается'),  -- Козлов в ВШЭ НН (основное)
(5, 1, 1, '2023-09-01', 'Обучается'),  -- Козлов также в ВШЭ Москва
(8, 4, 4, '2023-09-01', 'Обучается'),  -- Павлова в МГУ (основное)
(8, 5, 5, '2023-09-01', 'Обучается');  -- Павлова также в МФТИ

-- Преподаватели, которые работают в нескольких вузах (пример)
INSERT INTO app.teacher_institutions (teacher_id, institution_id, segment_id, employment_date, position, is_main_workplace) VALUES
(1, 1, 1, '2020-09-01', 'Профессор', true),    -- Иванов в ВШЭ Москва (основное)
(1, 4, 4, '2021-09-01', 'Профессор', false),   -- Иванов также в МГУ (по совместительству)
(3, 2, 2, '2019-09-01', 'Доцент', true),      -- Сидоров в ВШЭ СПб (основное)
(3, 6, 6, '2022-09-01', 'Доцент', false),     -- Сидоров также в РУДН (по совместительству)
(5, 3, 3, '2018-09-01', 'Доцент', true),      -- Смирнов в ВШЭ НН (основное)
(5, 1, 1, '2020-09-01', 'Доцент', false),     -- Смирнов также в ВШЭ Москва
(7, 4, 4, '2017-09-01', 'Профессор', true),   -- Батаев в МГУ (основное)
(7, 5, 5, '2019-09-01', 'Профессор', false),  -- Батаев также в МФТИ
(9, 5, 5, '2016-09-01', 'Профессор', true),   -- Алексеев в МФТИ (основное)
(9, 4, 4, '2018-09-01', 'Профессор', false);  -- Алексеев также в МГУ

--logon trigger
CREATE OR REPLACE FUNCTION audit.login_audit()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER --функция выполняется с правами её владельца, а не текущего пользователя, что даст вставку в аудит
AS $$
BEGIN
    INSERT INTO audit.login_log (login_time, username, client_ip)
    VALUES (
        CURRENT_TIMESTAMP,
        session_user,
        inet_client_addr()
    );
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END;
$$;
CREATE EVENT TRIGGER login_audit_tg
ON login
EXECUTE FUNCTION audit.login_audit();

--Логирование вызова функций с ошибкой
CREATE OR REPLACE FUNCTION audit.func_error_log(
    p_func_name VARCHAR(100),
    p_caller_role VARCHAR(100),
    p_input_params JSONB,
    p_success BOOLEAN
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'audit'
AS $$
BEGIN
    INSERT INTO audit.function_calls (function_name, caller_role, input_params, success)
    VALUES (p_func_name, p_caller_role, p_input_params, p_success);
END;
$$;

--SECURITY DEFINED functions

--Регистрация итоговой оценки
CREATE OR REPLACE FUNCTION app.register_final_grade(
    p_student_id INT,
    p_subject_id INT, 
    p_teacher_id INT,
    p_final_grade_type_id INT,
    p_final_grade_value VARCHAR(10),
    p_semester INT
)
RETURNS INT
SECURITY DEFINER
SET search_path = 'app, public'
LANGUAGE plpgsql
AS $$
DECLARE
    v_grade_id INT;
    v_student_exists BOOLEAN;
    v_teacher_exists BOOLEAN;
    v_subject_exists BOOLEAN;
    v_grade_type_exists BOOLEAN;
    v_allowed_values VARCHAR(255);
    v_current_role VARCHAR(30);
    v_call_id INT;
BEGIN
    --Проверка существования id
    SELECT EXISTS(SELECT 1 FROM app.students WHERE student_id = p_student_id) INTO v_student_exists;
    SELECT EXISTS(SELECT 1 FROM app.teachers WHERE teacher_id = p_teacher_id) INTO v_teacher_exists;
    SELECT EXISTS(SELECT 1 FROM ref.subjects WHERE subject_id = p_subject_id) INTO v_subject_exists;
    SELECT EXISTS(SELECT 1 FROM ref.final_grade_types WHERE final_grade_type_id = p_final_grade_type_id) INTO v_grade_type_exists;
    
    IF NOT v_student_exists THEN
        RAISE EXCEPTION 'Студент с ID % не найден', p_student_id;
    END IF;
    IF NOT v_teacher_exists THEN
        RAISE EXCEPTION 'Преподаватель с ID % не найден', p_teacher_id;
    END IF;
    IF NOT v_subject_exists THEN
        RAISE EXCEPTION 'Дисциплина с ID % не найдена', p_subject_id;
    END IF;
    IF NOT v_grade_type_exists THEN
        RAISE EXCEPTION 'Тип оценки с ID % не найден', p_final_grade_type_id;
    END IF;
    
    -- Проверка допустимых значений оценки
    SELECT allowed_values INTO v_allowed_values 
    FROM ref.final_grade_types 
    WHERE final_grade_type_id = p_final_grade_type_id;
    
    IF v_allowed_values NOT LIKE '%' || p_final_grade_value || '%' THEN
        RAISE EXCEPTION 'Оценка "%" недопустима для выбранной системы оценивания. Допустимые значения: %', 
            p_final_grade_value, v_allowed_values;
    END IF;
    
    -- Проверка семестра
    IF p_semester <= 0 THEN
        RAISE EXCEPTION 'Номер семестра должен быть положительным';
    END IF;
    
    -- Регистрация оценки
    INSERT INTO app.final_grades (
        student_id, subject_id, teacher_id, final_grade_type_id, 
        final_grade_value, semester
    ) VALUES (
        p_student_id, p_subject_id, p_teacher_id, p_final_grade_type_id,
        p_final_grade_value, p_semester
    ) RETURNING final_grade_id INTO v_grade_id;
    
    -- Получение роли, от которой могла быть вызвана функция
    SELECT m.rolname as role_name
    INTO v_current_role
    FROM pg_user u 
    JOIN pg_auth_members am ON u.usesysid = am.member
    JOIN pg_roles m ON am.roleid = m.oid
    WHERE u.usename = session_user
        AND has_function_privilege(m.rolname, 'app.register_final_grade(
        INT,
        INT, 
        INT,
        INT,
        VARCHAR(10),
        INT
    )', 'EXECUTE')
    LIMIT 1;

    -- Логирование вызова
    INSERT INTO audit.function_calls (function_name, caller_role, input_params, success)
    VALUES (
        'register_final_grade',
        v_current_role,
        jsonb_build_object(
            'student_id', p_student_id,
            'subject_id', p_subject_id,
            'teacher_id', p_teacher_id,
            'final_grade_type_id', p_final_grade_type_id,
            'final_grade_value', p_final_grade_value,
            'semester', p_semester
        ),
        true
    ) RETURNING call_id INTO v_call_id;
    
    RETURN v_grade_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION app.register_final_grade TO app_writer, dml_admin;


--Добавление документов студента
CREATE OR REPLACE FUNCTION app.add_student_document(
    p_student_id INT,
    p_document_type document_type_enum,
    p_document_series VARCHAR(20),
    p_document_number VARCHAR(50),
    p_issue_date DATE,
    p_issuing_authority TEXT
)
RETURNS INT
SECURITY DEFINER
SET search_path = 'app, public'
LANGUAGE plpgsql
AS $$
DECLARE
    v_document_id INT;
    v_student_exists BOOLEAN;
    v_student_status public.student_status_enum;
    v_document_exists BOOLEAN;
    v_current_role VARCHAR(30);
    v_call_id INT;
BEGIN
    -- Проверка существования студента
    SELECT EXISTS(SELECT 1 FROM app.students WHERE student_id = p_student_id), status
    INTO v_student_exists, v_student_status
    FROM app.students WHERE student_id = p_student_id;
    
    IF NOT v_student_exists THEN
        RAISE EXCEPTION 'Студент с ID % не найден', p_student_id;
    END IF;
    
    -- Проверка статуса студента
    IF v_student_status = 'Отчислен' THEN
        RAISE EXCEPTION 'Нельзя добавлять документы отчисленному студенту';
    END IF;
    
    -- Валидация номера документа
    IF p_document_number IS NULL THEN
        RAISE EXCEPTION 'Номер документа обязателен';
    END IF;
    
    -- Проверка уникальности документа для всех студентов
    SELECT EXISTS(
        SELECT 1 FROM app.student_documents 
        WHERE document_type = p_document_type 
        AND document_number = p_document_number
        AND (p_document_series IS NULL OR document_series = p_document_series)
    ) INTO v_document_exists;
    
    IF v_document_exists THEN
        RAISE EXCEPTION 'Документ типа "%" с номером % уже зарегистрирован в системе', 
            p_document_type, p_document_number;
    END IF;
    
    -- Проверка уникальности типа документа для студента (один тип документа на студента)
    IF EXISTS(
        SELECT 1 FROM app.student_documents 
        WHERE student_id = p_student_id 
        AND document_type = p_document_type
    ) THEN
        RAISE EXCEPTION 'У студента уже есть документ типа "%"', p_document_type;
    END IF;
    
    -- Добавление документа
    INSERT INTO app.student_documents (
        student_id, document_type, document_series, document_number,
        issue_date, issuing_authority
    ) VALUES (
        p_student_id, p_document_type, p_document_series, p_document_number,
        p_issue_date, p_issuing_authority
    ) RETURNING document_id INTO v_document_id;
    
    -- Получение роли, от которой могла быть вызвана функция
    SELECT m.rolname as role_name
    INTO v_current_role
    FROM pg_user u 
    JOIN pg_auth_members am ON u.usesysid = am.member
    JOIN pg_roles m ON am.roleid = m.oid
    WHERE u.usename = session_user
        AND has_function_privilege(m.rolname, 'app.add_student_document(
        INT,
        public.document_type_enum,
        VARCHAR(20),
        VARCHAR(50),
        DATE,
        TEXT
    )', 'EXECUTE')
    LIMIT 1;

    -- Логирование вызова
    INSERT INTO audit.function_calls (function_name, caller_role, input_params, success)
    VALUES (
        'add_student_document',
        v_current_role,
        jsonb_build_object(
            'student_id', p_student_id,
            'document_type', p_document_type,
            'document_series', p_document_series,
            'document_number', p_document_number,
            'issue_date', p_issue_date,
            'issuing_authority', p_issuing_authority
        ),
        true
    ) RETURNING call_id INTO v_call_id;

    RETURN v_document_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION app.add_student_document TO app_writer, dml_admin;


--Зачисление нового студента в группу
CREATE OR REPLACE FUNCTION app.enroll_student(
    p_last_name VARCHAR(50),
    p_first_name VARCHAR(50), 
    p_patronymic VARCHAR(50),
    p_email VARCHAR(255),
    p_phone_number VARCHAR(20),
    p_group_id INT
)
RETURNS INT
SECURITY DEFINER
SET search_path = 'app, public'
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_student_id INT;
    v_group_exists BOOLEAN;
    v_student_card_number VARCHAR(20);
    v_group_name VARCHAR(20);
    v_admission_year INT;
    v_student_count INT;
    v_current_role VARCHAR(30);
    v_call_id INT;
BEGIN
    -- Валидация обязательных полей
    IF p_last_name IS NULL OR p_first_name IS NULL THEN
        RAISE EXCEPTION 'Фамилия и имя студента обязательны';
    END IF;
    
    IF p_group_id IS NULL THEN
        RAISE EXCEPTION 'ID группы обязателен';
    END IF;
    
    -- Проверка существования группы
    SELECT EXISTS(SELECT 1 FROM app.study_groups WHERE group_id = p_group_id) INTO v_group_exists;
    IF NOT v_group_exists THEN
        RAISE EXCEPTION 'Группа с ID % не найдена', p_group_id;
    END IF;
    
    -- Проверка уникальности email
    IF p_email IS NOT NULL AND EXISTS(SELECT 1 FROM app.students WHERE email = p_email) THEN
        RAISE EXCEPTION 'Студент с email % уже существует', p_email;
    END IF;
    
    -- Получение данных группы для генерации номера студенческого
    SELECT group_name, admission_year INTO v_group_name, v_admission_year
    FROM app.study_groups WHERE group_id = p_group_id;
    
    -- Проверка количества студентов в группе (максимум 30)
    SELECT COUNT(*) INTO v_student_count FROM app.students WHERE group_id = p_group_id;
    IF v_student_count >= 30 THEN
        RAISE EXCEPTION 'Группа % переполнена. Максимальное количество студентов: 30', v_group_name;
    END IF;
    
    -- Генерация номера студенческого билета
    v_student_card_number := upper(substring(v_group_name from 1 for 3)) || 
                            v_admission_year || '-' || 
                            lpad((v_student_count + 1)::text, 3, '0');
    
    -- Зачисление студента
    INSERT INTO app.students (
        last_name, first_name, patronymic,
        student_card_number, email, phone_number,
        group_id, status
    ) VALUES (
        p_last_name, p_first_name, p_patronymic,
        v_student_card_number, p_email, p_phone_number,
        p_group_id, 'Обучается'
    ) RETURNING student_id INTO v_new_student_id;
    
    -- Получение роли, от которой могла быть вызвана функция
    SELECT m.rolname as role_name
    INTO v_current_role
    FROM pg_user u 
    JOIN pg_auth_members am ON u.usesysid = am.member
    JOIN pg_roles m ON am.roleid = m.oid
    WHERE u.usename = session_user
        AND has_function_privilege(m.rolname, 'app.enroll_student(
        VARCHAR(50),
        VARCHAR(50), 
        VARCHAR(50),
        VARCHAR(255),
        VARCHAR(20),
        INT
    )', 'EXECUTE')
    LIMIT 1;

    -- Логирование вызова
    INSERT INTO audit.function_calls (function_name, caller_role, input_params, success)
    VALUES (
        'enroll_student',
        v_current_role,
        jsonb_build_object(
            'last_name', p_last_name,
            'first_name', p_first_name,
            'patronymic', p_patronymic,
            'email', p_email,
            'phone_number', p_phone_number,
            'group_id', p_group_id
        ),
        true
    ) RETURNING call_id INTO v_call_id;

    RETURN v_new_student_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

-- Предоставление прав на выполнение
GRANT EXECUTE ON FUNCTION app.enroll_student TO app_writer, dml_admin;