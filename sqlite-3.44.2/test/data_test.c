#include <sqlite3.h>
#include <stdio.h>
#include <assert.h>

void test_sqlite3_open() {
    sqlite3 *db;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);
    printf("Test sqlite3_open passed.\n");
    sqlite3_close(db);
}

void test_sqlite3_exec() {
    sqlite3 *db;
    char *err_msg = 0;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);";
    rc = sqlite3_exec(db, sql, 0, 0, &err_msg);
    assert(rc == SQLITE_OK);

    printf("Test sqlite3_exec passed.\n");
    sqlite3_close(db);
}

void test_sqlite3_prepare_v2() {
    sqlite3 *db;
    sqlite3_stmt *stmt;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "SELECT 1;";
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, 0);
    assert(rc == SQLITE_OK);

    printf("Test sqlite3_prepare_v2 passed.\n");
    sqlite3_finalize(stmt);
    sqlite3_close(db);
}

void test_sqlite3_step() {
    sqlite3 *db;
    sqlite3_stmt *stmt;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "SELECT 1;";
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, 0);
    assert(rc == SQLITE_OK);

    rc = sqlite3_step(stmt);
    assert(rc == SQLITE_ROW);

    printf("Test sqlite3_step passed.\n");
    sqlite3_finalize(stmt);
    sqlite3_close(db);
}

void test_sqlite3_finalize() {
    sqlite3 *db;
    sqlite3_stmt *stmt;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "SELECT 1;";
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, 0);
    assert(rc == SQLITE_OK);

    rc = sqlite3_finalize(stmt);
    assert(rc == SQLITE_OK);

    printf("Test sqlite3_finalize passed.\n");
    sqlite3_close(db);
}

void test_sqlite3_close() {
    sqlite3 *db;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    rc = sqlite3_close(db);
    assert(rc == SQLITE_OK);

    printf("Test sqlite3_close passed.\n");
}

void test_sqlite3_last_insert_rowid() {
    sqlite3 *db;
    char *err_msg = 0;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);";
    rc = sqlite3_exec(db, sql, 0, 0, &err_msg);
    assert(rc == SQLITE_OK);

    sql = "INSERT INTO test (name) VALUES ('Alice');";
    rc = sqlite3_exec(db, sql, 0, 0, &err_msg);
    assert(rc == SQLITE_OK);

    sqlite3_int64 rowid = sqlite3_last_insert_rowid(db);
    assert(rowid == 1); // Ожидаем, что rowid будет 1

    printf("Test sqlite3_last_insert_rowid passed.\n");
    sqlite3_close(db);
}

void test_sqlite3_changes() {
    sqlite3 *db;
    char *err_msg = 0;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);";
    rc = sqlite3_exec(db, sql, 0, 0, &err_msg);
    assert(rc == SQLITE_OK);

    sql = "INSERT INTO test (name) VALUES ('Alice');";
    rc = sqlite3_exec(db, sql, 0, 0, &err_msg);
    assert(rc == SQLITE_OK);

    int changes = sqlite3_changes(db);
    assert(changes == 1); // Ожидаем, что changes будет 1

    printf("Test sqlite3_changes passed.\n");
    sqlite3_close(db);
}

void test_sqlite3_errmsg() {
    sqlite3 *db;
    int rc = sqlite3_open(":memory:", &db);
    assert(rc == SQLITE_OK);

    const char *sql = "INVALID SQL;";
    rc = sqlite3_exec(db, sql, 0, 0, 0);
    assert(rc != SQLITE_OK);

    const char *err_msg = sqlite3_errmsg(db);
    assert(err_msg != NULL);

    printf("Test sqlite3_errmsg passed.\n");
    sqlite3_close(db);
}

void test_sqlite3_free() {
    char *msg = sqlite3_mprintf("Test message");
    assert(msg != NULL);

    sqlite3_free(msg);

    printf("Test sqlite3_free passed.\n");
}

int main() {
    test_sqlite3_open();
    test_sqlite3_exec();
    test_sqlite3_prepare_v2();
    test_sqlite3_step();
    test_sqlite3_finalize();
    test_sqlite3_close();
    test_sqlite3_last_insert_rowid();
    test_sqlite3_changes();
    test_sqlite3_errmsg();
    test_sqlite3_free();

    printf("All tests passed!\n");
    return 0;
}
