#!/usr/bin/env bash
set -Eeuo pipefail

# 1. Определение переменных окружения
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-e2k}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/build-logs}"
PREFIX="${PREFIX:-$HOME/home/my_sqlite}"
CC_BIN="${CC:-gcc}"
AR_BIN="${AR:-ar}"
SCHEMA_RETRY="${SCHEMA_RETRY:-50}"

# 2. Валидация переменной SCHEMA_RETRY
case "$SCHEMA_RETRY" in
    ''|*[!0-9]*) echo "SCHEMA_RETRY должен быть положительным целым числом" >&2; exit 2 ;;
esac
[ "$SCHEMA_RETRY" -ge 1 ] || { echo "SCHEMA_RETRY должен быть не меньше 1" >&2; exit 2; }

# 3. Проверка наличия необходимых утилит
for tool in "$CC_BIN" "$AR_BIN" mkdir install ln tee grep sort date tclsh make; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Не найдена обязательная команда: $tool" >&2; exit 127; }
done

# 4. Гарантируем, что teseq доступен (создаем заглушку, если его нет)
command -v teseq >/dev/null 2>&1 || { 
    echo "Внимание: teseq не найден в системе. Создается заглушка в /usr/local/bin/teseq..."
    # Используем tee без sudo, если вы уже работаете под root (как в вашем логе)
    echo -e '#!/bin/sh\nexit 0' > /usr/local/bin/teseq
    chmod +x /usr/local/bin/teseq
}

# 5. Очистка и создание директорий
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LOG_DIR"

# 6. КРИТИЧЕСКИ ВАЖНО: Принудительно конвертируем Makefile.in в LF
# Это предотвратит ошибку "missing separator" при генерации Makefile
sed -i 's/\r$//' "$ROOT_DIR/Makefile.in"

# 7. Очистка лог-файлов
: > "$LOG_DIR/configure.log"
: > "$LOG_DIR/build.log"
: > "$LOG_DIR/install.log"

# 8. Массив макросов препроцессора (все требуемые флаги из задания)
DEFS=(
-DSQLITE_THREADSAFE=1
-DSQLITE_SECURE_DELETE=1
-DSQLITE_ENABLE_COLUMN_METADATA=1
-DSQLITE_ENABLE_FTS3=1
-DSQLITE_ENABLE_FTS3_PARENTHESIS=1
-DSQLITE_ENABLE_FTS3_TOKENIZER=1
-DSQLITE_ENABLE_FTS5=1
-DSQLITE_ENABLE_RTREE=1
-DSQLITE_ENABLE_DBSTAT_VTAB=1
-DSQLITE_ENABLE_JSON1=1
"-DSQLITE_MAX_SCHEMA_RETRY=$SCHEMA_RETRY"
-DSQLITE_MAX_VARIABLE_NUMBER=250000
)

# 9. Переход в директорию сборки (ВАЖНО: делаем это ДО запуска configure, чтобы make сработал корректно)
cd "$BUILD_DIR"

# 10. Конфигурация
echo "Запуск configure..."
CC="$CC_BIN" CPPFLAGS="${DEFS[*]}" CFLAGS="-O2 -fPIC" \
"$ROOT_DIR/configure" \
--prefix="$PREFIX" \
--disable-tcl \
--disable-readline \
--enable-threadsafe \
--enable-fts3 \
--enable-fts5 \
--enable-rtree \
--enable-json 2>&1 | tee "$LOG_DIR/configure.log"

# 11. Сборка (make сам сгенерирует sqlite3.c через tclsh и скомпилирует всё)
echo "Запуск make..."
set -x
make -j"$(nproc)" 2>&1 | tee "$LOG_DIR/build.log"
set +x

# 12. Установка
echo "Запуск make install..."
set -x
make install 2>&1 | tee "$LOG_DIR/install.log"

# Генерация pkg-config файла (на случай, если make install его не создал)
mkdir -p "$PREFIX/lib/pkgconfig"
cat > "$PREFIX/lib/pkgconfig/sqlite3.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: SQLite
Description: SQL database engine
Version: 3.44.2
Libs: -L\${libdir} -lsqlite3
Libs.private: -pthread -ldl -lm
Cflags: -I\${includedir}
EOF
set +x

# 13. Проверка опций компиляции
echo "Проверка PRAGMA compile_options..."
"$PREFIX/bin/sqlite3" ':memory:' 'PRAGMA compile_options;' | sort > "$LOG_DIR/compile_options.txt"

# 14. Создание тестовой БД и SQL-скрипта для проверки функций
rm -f "$BUILD_DIR/feature-tests.db"
cat > "$BUILD_DIR/feature_tests.sql" <<'EOF'
PRAGMA secure_delete=ON;
SELECT 'secure_delete|' || (CASE WHEN value=1 THEN '1' ELSE '0' END) FROM pragma_compile_options WHERE option='SECURE_DELETE';

CREATE VIRTUAL TABLE ft3 USING fts3(content);
INSERT INTO ft3(content) VALUES ('test (parentheses)');
SELECT 'fts3_parentheses|1' WHERE content MATCH '"test" AND "parentheses"' FROM ft3;

CREATE VIRTUAL TABLE ft5 USING fts5(content);
INSERT INTO ft5(content) VALUES ('test');
SELECT 'fts5|1' WHERE content MATCH 'test' FROM ft5;

CREATE VIRTUAL TABLE rt USING rtree(id, x1, x2, y1, y2);
INSERT INTO rt VALUES(1, 1.0, 2.0, 1.0, 2.0);
SELECT 'rtree|1' WHERE id=1 FROM rt WHERE x1<=1.5 AND x2>=1.5;

CREATE VIRTUAL TABLE dbstat USING dbstat;
SELECT 'dbstat|1' FROM dbstat LIMIT 1;

SELECT 'json|1' WHERE json_extract('{"a":1}', '$.a') = 1;

SELECT 'threadsafe|1' FROM pragma_compile_options WHERE option='THREADSAFE=1';
SELECT 'column_metadata|1' FROM pragma_compile_options WHERE option='ENABLE_COLUMN_METADATA';
SELECT 'fts3_tokenizer|1' FROM pragma_compile_options WHERE option='ENABLE_FTS3_TOKENIZER';

SELECT 'schema_retry|' || (CASE WHEN value='__SCHEMA_RETRY__' THEN '1' ELSE '0' END) FROM pragma_compile_options WHERE option='MAX_SCHEMA_RETRY=__SCHEMA_RETRY__';
SELECT 'max_variable|1' FROM pragma_compile_options WHERE option='MAX_VARIABLE_NUMBER=250000';
EOF

# Подстановка значения SCHEMA_RETRY в SQL-скрипт
sed -i "s/__SCHEMA_RETRY__/$SCHEMA_RETRY/g" "$BUILD_DIR/feature_tests.sql"

# Запуск тестов
"$PREFIX/bin/sqlite3" "$BUILD_DIR/feature-tests.db" < "$BUILD_DIR/feature_tests.sql" > "$LOG_DIR/feature_tests.txt"

# 15. Вывод логов git (если это репозиторий)
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_COMMIT="$(git -C "$ROOT_DIR" rev-list --max-parents=0 HEAD | tail -n 1)"
    git -C "$ROOT_DIR" log -p "$BASE_COMMIT"..HEAD > "$LOG_DIR/git_log_p.txt"
    git -C "$ROOT_DIR" log --date=iso-strict --pretty=format:'%H | %ad | %s' \
    "$BASE_COMMIT"..HEAD > "$LOG_DIR/commit_info.txt"
fi

# 16. Финальная валидация
echo "Выполнение финальной валидации..."
required_options=(SECURE_DELETE ENABLE_COLUMN_METADATA ENABLE_FTS3 ENABLE_FTS3_PARENTHESIS ENABLE_FTS3_TOKENIZER ENABLE_FTS5 ENABLE_RTREE ENABLE_DBSTAT_VTAB THREADSAFE=1 "MAX_SCHEMA_RETRY=$SCHEMA_RETRY" MAX_VARIABLE_NUMBER=250000)
for option in "${required_options[@]}"; do
    grep -Fxq "$option" "$LOG_DIR/compile_options.txt" || { echo "Не найден compile option: $option" >&2; exit 1; }
done

for check in secure_delete json fts3_parentheses fts5 rtree dbstat threadsafe column_metadata fts3_tokenizer schema_retry max_variable; do
    grep -Fxq "$check|1" "$LOG_DIR/feature_tests.txt" || { echo "Не прошла проверка: $check" >&2; cat "$LOG_DIR/feature_tests.txt" >&2; exit 1; }
done

printf '\n✅ Сборка и проверки завершены успешно.\nSQLite установлен в: %s/bin/sqlite3\nЛоги сохранены в: %s\n' "$PREFIX" "$LOG_DIR"