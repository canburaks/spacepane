#ifndef PREVIEW_SQLITE_SAFETY_H
#define PREVIEW_SQLITE_SAFETY_H
#include <sqlite3.h>

/// Public SQLite varargs APIs need a narrow typed C bridge for Swift callers.
int preview_sqlite_configure(sqlite3 *database);
#endif
