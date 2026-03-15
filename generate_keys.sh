#!/bin/bash

# Скрипт для генерации PGP ключей для PostgreSQL
# Запускать на хосте до первого запуска контейнера

set -e

# Директория для ключей (будет смонтирована в контейнер)
KEY_DIR="./pgp_keys"

echo "=== Генерация PGP ключей для PostgreSQL ==="

# Создаем директорию, если её нет
mkdir -p ${KEY_DIR}
echo "Директория ${KEY_DIR} создана."

# Удаляем старые ключи, если они есть
rm -f ${KEY_DIR}/*.key ${KEY_DIR}/*.asc

# --- 1. Генерация симметричного ключа (парольная фраза) ---
SYMM_KEY_FILE="${KEY_DIR}/symmetric.key"
# Генерируем случайный пароль (44 символа для надежности) и сохраняем в файл
echo "sychuk_ab-320" > ${SYMM_KEY_FILE}
echo "Симметричный ключ сгенерирован и сохранен в ${SYMM_KEY_FILE}"

# --- 2. Генерация асимметричной пары ключей (открытый/закрытый) для OpenPGP ---
# Создаем временную папку для gpg
GNUPGHOME_TEMP="${KEY_DIR}/gnupg_temp"
mkdir -p ${GNUPGHOME_TEMP}
chmod 700 ${GNUPGHOME_TEMP}

# Параметры ключа
KEY_NAME="Education DB Key"
KEY_COMMENT="Sychuk Keys"
KEY_EMAIL="sychuk@nstu.ru"
KEY_EXPIRE="2y" # Ключ действителен 2 года

echo "Генерация асимметричной пары ключей в ${GNUPGHOME_TEMP}..."

# Генерируем ключ в неинтерактивном режиме
# Используем переменную окружения для указания домашней папки gnupg
export GNUPGHOME=${GNUPGHOME_TEMP}
cat >${GNUPGHOME_TEMP}/gen-key-script <<EOF
    Key-Type: RSA
    Key-Length: 2048
    Subkey-Type: RSA
    Subkey-Length: 2048
    Name-Real: ${KEY_NAME}
    Name-Comment: ${KEY_COMMENT}
    Name-Email: ${KEY_EMAIL}
    Expire-Date: ${KEY_EXPIRE}
    %no-ask-passphrase
    %no-protection
    %commit
EOF

gpg --batch --generate-key ${GNUPGHOME_TEMP}/gen-key-script

# Получаем ID ключа (длинный)
KEY_ID=$(gpg --list-keys --with-colons "${KEY_EMAIL}" | awk -F: '/^pub/ {print $5}')
echo "Сгенерирован ключ с ID: ${KEY_ID}"

# Экспортируем открытый ключ в читаемом для БД формате (ASCII)
gpg --export -a "${KEY_EMAIL}" > ${KEY_DIR}/public.key
echo "Открытый ключ экспортирован в ${KEY_DIR}/public.key"

# Экспортируем секретный ключ в читаемом для БД формате (ASCII)
gpg --export-secret-key -a "${KEY_EMAIL}" > ${KEY_DIR}/private.key
echo "Секретный ключ экспортирован в ${KEY_DIR}/private.key"

# Удаляем временную папку gnupg
rm -rf ${GNUPGHOME_TEMP}
unset GNUPGHOME

# Устанавливаем права доступа, чтобы ключи были доступны для чтения внутри контейнера
chmod 644 ${KEY_DIR}/*.key ${KEY_DIR}/*.asc 2>/dev/null || true

echo ""
echo "=== Генерация ключей успешно завершена ==="
echo "Симметричный ключ: ${SYMM_KEY_FILE}"
echo "Открытый ключ: ${KEY_DIR}/public.key"
echo "Приватный ключ: ${KEY_DIR}/private.key (ХРАНИТЕ В БЕЗОПАСНОСТИ!)"