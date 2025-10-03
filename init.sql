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
    grade_value VARCHAR(5) NOT NULL,
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



--заполнение таблицы teachers, поскольку rector_id берется из нее

INSERT INTO app.teachers (last_name, first_name, patronymic, academic_degree, academic_title, email, phone_number) VALUES
('Иванов', 'Петр', 'Сергеевич', 'Доктор наук', 'Профессор', 'ivanov@university.ru', '+7-900-123-45-67'),
('Петрова', 'Мария', 'Ивановна', 'Кандидат наук', 'Доцент', 'petrova@university.ru', '+7-900-123-45-68'),
('Сидоров', 'Алексей', 'Владимирович', 'Кандидат наук', 'Доцент', 'sidorov@university.ru', '+7-900-123-45-69'),
('Кузнецова', 'Елена', 'Анатольевна', 'Доктор наук', 'Профессор', 'kuznetsova@university.ru', '+7-900-123-45-70'),
('Смирнов', 'Дмитрий', 'Петрович', 'Кандидат наук', 'Доцент', 'smirnov@university.ru', '+7-900-123-45-71'),
('Федорова', 'Ольга', 'Викторовна', 'Нет', 'Доцент', 'fedorova@university.ru', '+7-900-123-45-72'),
('Батаев', 'Анатолий', 'Андреевич', 'Доктор наук', 'Профессор', 'rector@nstu.ru', '+7-383-346-08-43'),
('Васильева', 'Анна', 'Сергеевна', 'Нет', 'Доцент', 'vasilyeva@university.ru', '+7-900-123-45-74'),
('Алексеев', 'Игорь', 'Валентинович', 'Доктор наук', 'Профессор', 'alekseev@university.ru', '+7-900-123-45-75'),
('Николаева', 'Татьяна', 'Борисовна', 'Кандидат наук', 'Доцент', 'nikolaeva@university.ru', '+7-900-123-45-76');

--заполнение таблиц-справочников

INSERT INTO ref.educational_institutions (institution_id, institution_name, short_name, legal_address, rector_id) VALUES
(1, 'Национальный исследовательский университет "Высшая школа экономики"', 'НИУ ВШЭ', 'г. Москва, ул. Мясницкая, д. 20', 1),
(2, 'Московский государственный университет имени М.В. Ломоносова', 'МГУ', 'г. Москва, Ленинские горы, д. 1', 4),
(3, 'Московский физико-технический институт', 'МФТИ', 'г. Москва, ул. Климентовский пер, д. 1', 9),
(4, 'Российский университет дружбы народов', 'РУДН', 'г. Москва, ул. Миклухо-Маклая, д. 6', 5),
(5, 'Новосибирский государственный технический университет', 'НГТУ', 'г. Новосибирск, пр-т К.Маркса, д. 20', 7);

INSERT INTO ref.faculties (faculty_id, faculty_name, dean_id, institution_id) VALUES
(1, 'Факультет компьютерных наук', 2, 1),
(2, 'Экономический факультет', 3, 1),
(3, 'Механико-математический факультет', 6, 2),
(4, 'Факультет вычислительной математики и кибернетики', 8, 2),
(5, 'Факультет общей и прикладной физики', 10, 3),
(6, 'Факультет инженерный', 1, 4),
(7, 'Факультет экономический', 4, 4),
(8, 'Факультет робототехники', 7, 5),
(9, 'Факультет информатики', 9, 5),
(10, 'Факультет прикладной математики', 5, 3);

INSERT INTO ref.departments (department_id, department_name, head_of_department_id, faculty_id) VALUES
(1, 'Кафедра программной инженерии', 1, 1),
(2, 'Кафедра анализа данных', 2, 1),
(3, 'Кафедра экономической теории', 3, 2),
(4, 'Кафедра высшей математики', 4, 3),
(5, 'Кафедра системного программирования', 5, 4),
(6, 'Кафедра теоретической физики', 6, 5),
(7, 'Кафедра инженерной механики', 7, 6),
(8, 'Кафедра финансов', 8, 7),
(9, 'Кафедра робототехнических систем', 9, 8),
(10, 'Кафедра искусственного интеллекта', 10, 9);

INSERT INTO ref.study_groups (group_id, group_name, admission_year, faculty_id) VALUES
(1, 'АБ-320', 2023, 1),
(2, 'ПИ-02', 2023, 1),
(3, 'ЭК-01', 2023, 2),
(4, 'ЭК-02', 2023, 2),
(5, 'ММ-01', 2023, 3),
(6, 'ВМК-01', 2023, 4),
(7, 'ФИЗ-01', 2023, 5),
(8, 'ИНЖ-01', 2023, 6),
(9, 'РОБ-01', 2023, 8),
(10, 'ИИ-01', 2023, 9);

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

--заполнение основных таблиц
DELETE FROM app.students;
INSERT INTO app.students (last_name, first_name, patronymic, student_card_number, email, phone_number, group_id, status) VALUES
('Соколов', 'Александр', 'Игоревич', 'СТ-2023-001', 'sokolov@student.ru', '+7-900-200-01-01', 1, 'Обучается'),
('Орлова', 'Виктория', 'Сергеевна', 'СТ-2023-002', 'orlova@student.ru', '+7-900-200-01-02', 1, 'Обучается'),
('Лебедев', 'Максим', 'Александрович', 'СТ-2023-003', 'lebedev@student.ru', '+7-900-200-01-03', 2, 'Обучается'),
('Егорова', 'Анастасия', 'Дмитриевна', 'СТ-2023-004', 'egorova@student.ru', '+7-900-200-01-04', 2, 'Академический отпуск'),
('Козлов', 'Артем', 'Витальевич', 'СТ-2023-005', 'kozlov@student.ru', '+7-900-200-01-05', 3, 'Обучается'),
('Новикова', 'Екатерина', 'Андреевна', 'СТ-2023-006', 'novikova@student.ru', '+7-900-200-01-06', 3, 'Обучается'),
('Морозов', 'Иван', 'Олегович', 'СТ-2023-007', 'morozov@student.ru', '+7-900-200-01-07', 4, 'Отчислен'),
('Павлова', 'София', 'Романовна', 'СТ-2023-008', 'pavlova@student.ru', '+7-900-200-01-08', 4, 'Обучается'),
('Волков', 'Кирилл', 'Иванович', 'СТ-2023-009', 'volkov@student.ru', '+7-900-200-01-09', 5, 'Обучается'),
('Андреева', 'Дарья', 'Викторовна', 'СТ-2023-010', 'andreeva@student.ru', '+7-900-200-01-10', 5, 'Выпустился');

DELETE FROM app.teacher_departments;
INSERT INTO app.teacher_departments (teacher_id, department_id, is_main, position) VALUES
(1, 1, true, 'Профессор'),
(2, 2, true, 'Доцент'),
(3, 3, true, 'Доцент'),
(4, 4, true, 'Профессор'),
(5, 5, true, 'Доцент'),
(6, 6, true, 'Старший преподаватель'),
(7, 7, true, 'Доцент'),
(8, 8, true, 'Старший преподаватель'),
(9, 9, true, 'Профессор'),
(10, 10, true, 'Доцент');

DELETE FROM app.academic_plans;
INSERT INTO app.academic_plans (group_id, subject_id, semester, total_hours, lecture_hours, practice_hours, control_type) VALUES
(1, 1, 1, 144, 72, 72, 'Экзамен'),
(1, 2, 1, 108, 54, 54, 'Зачет'),
(2, 3, 1, 144, 72, 72, 'Экзамен'),
(2, 4, 1, 90, 45, 45, 'Зачет'),
(3, 5, 2, 120, 60, 60, 'Экзамен'),
(3, 6, 2, 96, 48, 48, 'Зачет'),
(4, 7, 2, 132, 66, 66, 'Экзамен'),
(4, 8, 2, 84, 42, 42, 'Зачет'),
(5, 9, 3, 156, 78, 78, 'Экзамен'),
(5, 10, 3, 102, 51, 51, 'Зачет');

DELETE FROM app.final_grades;
INSERT INTO app.final_grades (student_id, subject_id, teacher_id, final_grade_type_id, final_grade_value, grade_date, semester) VALUES
(1, 1, 1, 1, '5', '2024-01-20', 1),
(2, 1, 1, 1, '4', '2024-01-20', 1),
(3, 3, 2, 1, '5', '2024-01-21', 1),
(4, 4, 3, 1, '3', '2024-01-22', 1),
(5, 5, 4, 1, '4', '2024-06-15', 2),
(6, 6, 5, 1, '5', '2024-06-16', 2),
(7, 7, 6, 1, '2', '2024-06-17', 2),
(8, 8, 7, 1, '4', '2024-06-18', 2),
(9, 9, 8, 1, '5', '2024-12-20', 3),
(10, 10, 9, 1, '3', '2024-12-21', 3);

DELETE FROM app.interim_grades;
INSERT INTO app.interim_grades (student_id, subject_id, teacher_id, grade_value, grade_date, grade_description, semester) VALUES
(1, 1, 1, '5', '2023-10-15', 'Контрольная работа 1', 1),
(1, 1, 1, '4', '2023-11-20', 'Контрольная работа 2', 1),
(2, 1, 1, '4', '2023-10-15', 'Контрольная работа 1', 1),
(3, 3, 2, '5', '2023-10-16', 'Контрольная работа 1', 1),
(5, 5, 4, '4', '2024-03-10', 'Лабораторная работа', 2),
(6, 6, 5, '5', '2024-03-12', 'Практическое задание', 2),
(8, 8, 7, '3', '2024-03-15', 'Тестирование', 2),
(9, 9, 8, '5', '2024-09-20', 'Курсовая работа', 3),
(9, 9, 8, '4', '2024-10-25', 'Проект', 3),
(10, 10, 9, '3', '2024-09-22', 'Семинар', 3);

DELETE FROM app.class_schedule;
INSERT INTO app.class_schedule (group_id, subject_id, teacher_id, week_number, day_of_week, start_time, end_time, classroom, building_number, lesson_type) VALUES
(1, 1, 1, 1, 'Понедельник', '09:00', '10:30', '101', '1', 'Лекция'),
(1, 2, 1, 1, 'Среда', '10:40', '12:10', '201', '1', 'Практика'),
(2, 3, 2, 1, 'Вторник', '09:00', '10:30', '102', '1', 'Лекция'),
(2, 4, 3, 1, 'Четверг', '13:30', '15:00', '301', '2', 'Лабораторная'),
(3, 5, 4, 2, 'Понедельник', '15:10', '16:40', '401', '3', 'Лекция'),
(3, 6, 5, 2, 'Пятница', '12:20', '13:50', '501', '3', 'Практика'),
(4, 7, 6, 2, 'Среда', '16:50', '18:20', '601', '4', 'Лабораторная'),
(4, 8, 7, 2, 'Суббота', '10:40', '12:10', '701', '4', 'Лекция'),
(5, 9, 8, 3, 'Вторник', '13:30', '15:00', '801', '5', 'Практика'),
(5, 10, 9, 3, 'Четверг', '15:10', '16:40', '901', '5', 'Лабораторная');

INSERT INTO app.student_documents (student_id, document_type, document_series, document_number, issue_date, issuing_authority) VALUES
(1, 'Паспорт', '4501', '123456', '2018-04-15', 'ОУФМС России по г. Москве'),
(1, 'Аттестат', NULL, '789-123', '2022-06-25', 'Гимназия №1 г. Москвы'),
(2, 'Паспорт', '4502', '234567', '2019-05-20', 'ОУФМС России по г. Москве'),
(2, 'Аттестат', NULL, '789-124', '2022-06-25', 'Лицей №2 г. Москвы'),
(3, 'Паспорт', '4503', '345678', '2020-03-10', 'ОУФМС России по г. Москве'),
(3, 'Мед. справка', NULL, '086У-2023', '2023-08-15', 'Поликлиника №1'),
(4, 'Паспорт', '4504', '456789', '2018-07-12', 'ОУФМС России по г. Москве'),
(4, 'ИНН', NULL, '1234567890', '2023-09-01', 'ИФНС России по г. Москве'),
(5, 'Паспорт', '4505', '567890', '2019-11-05', 'ОУФМС России по г. Москве'),
(5, 'СНИЛС', NULL, '123-456-789-01', '2023-09-01', 'ПФР по г. Москве');

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
    
    --Проверка существования id
    SELECT EXISTS(SELECT 1 FROM app.students WHERE student_id = p_student_id) INTO v_student_exists;
    SELECT EXISTS(SELECT 1 FROM app.teachers WHERE teacher_id = p_teacher_id) INTO v_teacher_exists;
    SELECT EXISTS(SELECT 1 FROM ref.subjects WHERE subject_id = p_subject_id) INTO v_subject_exists;
    SELECT EXISTS(SELECT 1 FROM ref.final_grade_types WHERE final_grade_type_id = p_final_grade_type_id) INTO v_grade_type_exists;
    
    IF NOT v_student_exists THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Студент с ID % не найден', p_student_id;
    END IF;
    IF NOT v_teacher_exists THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Преподаватель с ID % не найден', p_teacher_id;
    END IF;
    IF NOT v_subject_exists THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Дисциплина с ID % не найдена', p_subject_id;
    END IF;
    IF NOT v_grade_type_exists THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Тип оценки с ID % не найден', p_final_grade_type_id;
    END IF;
    
    -- Проверка допустимых значений оценки
    SELECT allowed_values INTO v_allowed_values 
    FROM ref.final_grade_types 
    WHERE final_grade_type_id = p_final_grade_type_id;
    
    IF v_allowed_values NOT LIKE '%' || p_final_grade_value || '%' THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Оценка "%" недопустима для выбранной системы оценивания. Допустимые значения: %', 
            p_final_grade_value, v_allowed_values;
    END IF;
    
    -- Проверка семестра
    IF p_semester <= 0 THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
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
    
    RETURN v_grade_id;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
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
    
    -- Проверка существования студента
    SELECT EXISTS(SELECT 1 FROM app.students WHERE student_id = p_student_id), status
    INTO v_student_exists, v_student_status
    FROM app.students WHERE student_id = p_student_id;
    
    IF NOT v_student_exists THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Студент с ID % не найден', p_student_id;
    END IF;
    
    -- Проверка статуса студента
    IF v_student_status = 'Отчислен' THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Нельзя добавлять документы отчисленному студенту';
    END IF;
    
    -- Валидация номера документа
    IF p_document_number IS NULL THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
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
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Документ типа "%" с номером % уже зарегистрирован в системе', 
            p_document_type, p_document_number;
    END IF;
    
    -- Проверка уникальности типа документа для студента (один тип документа на студента)
    IF EXISTS(
        SELECT 1 FROM app.student_documents 
        WHERE student_id = p_student_id 
        AND document_type = p_document_type
    ) THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
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
    
    RETURN v_document_id;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
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
    
    -- Валидация обязательных полей
    IF p_last_name IS NULL OR p_first_name IS NULL THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Фамилия и имя студента обязательны';
    END IF;
    
    IF p_group_id IS NULL THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'ID группы обязателен';
    END IF;
    
    -- Проверка существования группы
    SELECT EXISTS(SELECT 1 FROM ref.study_groups WHERE group_id = p_group_id) INTO v_group_exists;
    IF NOT v_group_exists THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Группа с ID % не найдена', p_group_id;
    END IF;
    
    -- Проверка уникальности email
    IF p_email IS NOT NULL AND EXISTS(SELECT 1 FROM app.students WHERE email = p_email) THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE EXCEPTION 'Студент с email % уже существует', p_email;
    END IF;
    
    -- Получение данных группы для генерации номера студенческого
    SELECT group_name, admission_year INTO v_group_name, v_admission_year
    FROM ref.study_groups WHERE group_id = p_group_id;
    
    -- Проверка количества студентов в группе (максимум 30)
    SELECT COUNT(*) INTO v_student_count FROM app.students WHERE group_id = p_group_id;
    IF v_student_count >= 30 THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
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
    
    RETURN v_new_student_id;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE audit.function_calls SET success = false WHERE call_id = v_call_id;
        RAISE;
END;
$$;

-- Предоставление прав на выполнение
GRANT EXECUTE ON FUNCTION app.enroll_student TO app_writer, dml_admin;