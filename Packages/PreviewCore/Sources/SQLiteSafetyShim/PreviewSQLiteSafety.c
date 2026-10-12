#include "PreviewSQLiteSafety.h"

int preview_sqlite_configure(sqlite3 *database) {
    int effective = 0;
    int result = sqlite3_db_config(database, SQLITE_DBCONFIG_DEFENSIVE, 1, &effective);
    if (result != SQLITE_OK || effective != 1) return result == SQLITE_OK ? SQLITE_ERROR : result;
    result = sqlite3_db_config(database, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, &effective);
    if (result != SQLITE_OK || effective != 0) return result == SQLITE_OK ? SQLITE_ERROR : result;
    if (!sqlite3_compileoption_used("OMIT_LOAD_EXTENSION")) {
        result = sqlite3_db_config(database, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 0, &effective);
        if (result != SQLITE_OK || effective != 0) return result == SQLITE_OK ? SQLITE_ERROR : result;
    }
    return SQLITE_OK;
}
