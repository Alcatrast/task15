#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-e2k}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/build-logs}"
PREFIX="${PREFIX:-$HOME/home/my_sqlite}"
CC_BIN="${CC:-gcc}"
AR_BIN="${AR:-ar}"
SCHEMA_RETRY="${SCHEMA_RETRY:-50}"

case "$SCHEMA_RETRY" in
    ''|*[!0-9]*) echo "SCHEMA_RETRY должен быть положительным целым числом" >&2; exit 2 ;;
esac
[ "$SCHEMA_RETRY" -ge 1 ] || { echo "SCHEMA_RETRY должен быть не меньше 1" >&2; exit 2; }

for tool in "$CC_BIN" "$AR_BIN" mkdir install ln tee grep sort date tclsh make; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Не найдена обязательная команда: $tool" >&2; exit 127; }
done

# Патчим configure, чтобы отключить жесткую проверку teseq (используется только для docs)
sed -i 's|as_fn_error.*teseq is required.*|:|' "$ROOT_DIR/configure"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LOG_DIR"
: > "$LOG_DIR/configure.log"
: > "$LOG_DIR/build.log"
: > "$LOG_DIR/install.log"

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

# ПЕРЕНЕСЕНО СЮДА: Смена директории ДО создания subshell для логов
cd "$BUILD_DIR"

{
echo "Дата: $(date -Iseconds)"
echo "Корень исходников: $ROOT_DIR"
echo "Префикс установки: $PREFIX"
echo "Компилятор: $CC_BIN"
echo "config.guess: $($ROOT_DIR/config.guess 2>&1 || true)"
echo "SCHEMA_RETRY: $SCHEMA_RETRY"
echo

# УБРАНО TCLSH_CMD=:, чтобы configure сам нашел tclsh8.6 и сгенерировал sqlite3.c
CC="$CC_BIN" CPPFLAGS="${DEFS[*]}" CFLAGS="-O2 -fPIC" \
"$ROOT_DIR/configure" \
--prefix="$PREFIX" \
--disable-tcl \
--disable-readline \
--enable-threadsafe \
--enable-fts3 \
--enable-fts5 \
--enable-rtree \
--enable-json
} 2>&1 | tee "$LOG_DIR/configure.log"

{
set -x
make -j"$(nproc)"
set +x
} 2>&1 | tee "$LOG_DIR/build.log"

{
set -x
make install

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
} 2>&1 | tee "$LOG_DIR/install.log"

"$PREFIX/bin/sqlite3" ':memory:' 'PRAGMA compile_options;' | sort > "$LOG_DIR/compile_options.txt"

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

sed -i "s/__SCHEMA_RETRY__/$SCHEMA_RETRY/g" "$BUILD_DIR/feature_tests.sql"
"$PREFIX/bin/sqlite3" "$BUILD_DIR/feature-tests.db" < "$BUILD_DIR/feature_tests.sql" > "$LOG_DIR/feature_tests.txt"

if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_COMMIT="$(git -C "$ROOT_DIR" rev-list --max-parents=0 HEAD | tail -n 1)"
    git -C "$ROOT_DIR" log -p "$BASE_COMMIT"..HEAD > "$LOG_DIR/git_log_p.txt"
    git -C "$ROOT_DIR" log --date=iso-strict --pretty=format:'%H | %ad | %s' \
    "$BASE_COMMIT"..HEAD > "$LOG_DIR/commit_info.txt"
fi

required_options=(SECURE_DELETE ENABLE_COLUMN_METADATA ENABLE_FTS3 ENABLE_FTS3_PARENTHESIS ENABLE_FTS3_TOKENIZER ENABLE_FTS5 ENABLE_RTREE ENABLE_DBSTAT_VTAB THREADSAFE=1 "MAX_SCHEMA_RETRY=$SCHEMA_RETRY" MAX_VARIABLE_NUMBER=250000)
for option in "${required_options[@]}"; do
    grep -Fxq "$option" "$LOG_DIR/compile_options.txt" || { echo "Не найден compile option: $option" >&2; exit 1; }
done

for check in secure_delete json fts3_parentheses fts5 rtree dbstat threadsafe column_metadata fts3_tokenizer schema_retry max_variable; do
    grep -Fxq "$check|1" "$LOG_DIR/feature_tests.txt" || { echo "Не прошла проверка: $check" >&2; cat "$LOG_DIR/feature_tests.txt" >&2; exit 1; }
done

printf '\nСборка и проверки завершены успешно.\nSQLite: %s/bin/sqlite3\nЛоги: %s\n' "$PREFIX" "$LOG_DIR"