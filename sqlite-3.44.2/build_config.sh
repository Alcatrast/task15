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
for tool in "$CC_BIN" "$AR_BIN" mkdir install ln tee grep sort date; do
command -v "$tool" >/dev/null 2>&1 || { echo "Не найдена обязательная команда: $tool" >&2; exit 127; }
done
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LOG_DIR"
: > "$LOG_DIR/configure.log"
: > "$LOG_DIR/build.log"
: > "$LOG_DIR/install.log"
DEFS=(
-DSQLITE_OS_UNIX=1
-DSQLITE_THREADSAFE=1
-DSQLITE_SECURE_DELETE=1
-DSQLITE_ENABLE_COLUMN_METADATA=1
-DSQLITE_ENABLE_FTS3=1
-DSQLITE_ENABLE_FTS3_PARENTHESIS=1
-DSQLITE_ENABLE_FTS3_TOKENIZER=1
-DSQLITE_ENABLE_FTS4=1
-DSQLITE_ENABLE_FTS5=1
-DSQLITE_ENABLE_RTREE=1
-DSQLITE_ENABLE_DBSTAT_VTAB=1
"-DSQLITE_MAX_SCHEMA_RETRY=$SCHEMA_RETRY"
-DSQLITE_MAX_VARIABLE_NUMBER=250000
)
read -r -a USER_CFLAGS <<< "${CFLAGS:--O2 -fPIC}"
read -r -a USER_LDFLAGS <<< "${LDFLAGS:-}"
LIBS=(-pthread -ldl -lm)
{
echo "Дата: $(date -Iseconds)"
echo "Корень исходников: $ROOT_DIR"
echo "Префикс установки: $PREFIX"
echo "Компилятор: $CC_BIN"
echo "config.guess: $($ROOT_DIR/config.guess 2>&1 || true)"
echo "SCHEMA_RETRY: $SCHEMA_RETRY"
echo "teseq необязателен; apt не вызывается."
echo
cd "$BUILD_DIR"
TCLSH_CMD=: TCLLIBDIR="$PREFIX/lib/sqlite3" CC="$CC_BIN" CPPFLAGS="${DEFS[*]}" \
"$ROOT_DIR/configure" \
--prefix="$PREFIX" --disable-tcl --disable-readline \
--enable-threadsafe --enable-fts3 --enable-fts5 --enable-rtree --enable-json
} 2>&1 | tee "$LOG_DIR/configure.log"
{
set -x
"$CC_BIN" "${USER_CFLAGS[@]}" "${DEFS[@]}" -I"$ROOT_DIR/amalgamation" \
-c "$ROOT_DIR/amalgamation/sqlite3.c" -o "$BUILD_DIR/sqlite3.o"
"$AR_BIN" rcs "$BUILD_DIR/libsqlite3.a" "$BUILD_DIR/sqlite3.o"
"$CC_BIN" -shared "${USER_LDFLAGS[@]}" -Wl,-soname,libsqlite3.so.0 \
-o "$BUILD_DIR/libsqlite3.so.0" "$BUILD_DIR/sqlite3.o" "${LIBS[@]}"
ln -sfn libsqlite3.so.0 "$BUILD_DIR/libsqlite3.so"
"$CC_BIN" "${USER_CFLAGS[@]}" "${DEFS[@]}" -I"$ROOT_DIR/amalgamation" \
"$ROOT_DIR/amalgamation/shell.c" "$BUILD_DIR/sqlite3.o" \
"${USER_LDFLAGS[@]}" "${LIBS[@]}" -o "$BUILD_DIR/sqlite3"
set +x
} 2>&1 | tee "$LOG_DIR/build.log"
{
set -x
mkdir -p "$PREFIX/bin" "$PREFIX/lib/pkgconfig" "$PREFIX/include" "$PREFIX/share/man/man1"
install -m 0755 "$BUILD_DIR/sqlite3" "$PREFIX/bin/sqlite3"
install -m 0644 "$BUILD_DIR/libsqlite3.a" "$PREFIX/lib/libsqlite3.a"
install -m 0755 "$BUILD_DIR/libsqlite3.so.0" "$PREFIX/lib/libsqlite3.so.0"
ln -sfn libsqlite3.so.0 "$PREFIX/lib/libsqlite3.so"
install -m 0644 "$ROOT_DIR/amalgamation/sqlite3.h" "$PREFIX/include/sqlite3.h"
install -m 0644 "$ROOT_DIR/amalgamation/sqlite3ext.h" "$PREFIX/include/sqlite3ext.h"
install -m 0644 "$ROOT_DIR/sqlite3.1" "$PREFIX/share/man/man1/sqlite3.1"
set +x
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
} 2>&1 | tee "$LOG_DIR/install.log"
"$PREFIX/bin/sqlite3" ':memory:' 'PRAGMA compile_options;' | sort > "$LOG_DIR/compile_options.txt"
rm -f "$BUILD_DIR/feature-tests.db"
sed "s/__SCHEMA_RETRY__/$SCHEMA_RETRY/g" "$ROOT_DIR/feature_tests.sql" > "$BUILD_DIR/feature_tests.sql"
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
printf '
Сборка и проверки завершены.
SQLite: %s/bin/sqlite3
Логи: %s
' "$PREFIX" "$LOG_DIR"
