const c = @import("c.zig");

pub const Error = error{
    // Generic error
    SQLITE_ERROR,
    // Internal logic error in SQLite
    SQLITE_INTERNAL,
    // Access permission denied
    SQLITE_PERM,
    // Callback routine requested an abort
    SQLITE_ABORT,
    // The database file is locked
    SQLITE_BUSY,
    // A table in the database is locked
    SQLITE_LOCKED,
    // A malloc() failed
    SQLITE_NOMEM,
    // Attempt to write a readonly database
    SQLITE_READONLY,
    // Operation terminated by sqlite3_interrupt()
    SQLITE_INTERRUPT,
    // Some kind of disk I/O error occurred
    SQLITE_IOERR,
    // The database disk image is malformed
    SQLITE_CORRUPT,
    // Unknown opcode in sqlite3_file_control()
    SQLITE_NOTFOUND,
    // Insertion failed because database is full
    SQLITE_FULL,
    // Unable to open the database file
    SQLITE_CANTOPEN,
    // Database lock protocol error
    SQLITE_PROTOCOL,
    // Internal use only
    SQLITE_EMPTY,
    // The database schema changed
    SQLITE_SCHEMA,
    // String or BLOB exceeds size limit
    SQLITE_TOOBIG,
    // Abort due to constraint violation
    SQLITE_CONSTRAINT,
    // Data type mismatch
    SQLITE_MISMATCH,
    // Library used incorrectly
    SQLITE_MISUSE,
    // Uses OS features not supported on host
    SQLITE_NOLFS,
    // Authorization denied
    SQLITE_AUTH,
    // Not used
    SQLITE_FORMAT,
    // 2nd parameter to sqlite3_bind out of range
    SQLITE_RANGE,
    // File opened that is not a database file
    SQLITE_NOTADB,
    // Notifications from sqlite3_log()
    SQLITE_NOTICE,
    // Warnings from sqlite3_log()
    SQLITE_WARNING,
    // sqlite3_step() has another row ready
    SQLITE_ROW,
    // sqlite3_step() has finished executing
    SQLITE_DONE,
};

pub fn getError(code: c_int) Error {
    return switch (code & 0xFF) {
        c.SQLITE_ERROR => Error.SQLITE_ERROR,
        c.SQLITE_INTERNAL => Error.SQLITE_INTERNAL,
        c.SQLITE_PERM => Error.SQLITE_PERM,
        c.SQLITE_ABORT => Error.SQLITE_ABORT,
        c.SQLITE_BUSY => Error.SQLITE_BUSY,
        c.SQLITE_LOCKED => Error.SQLITE_LOCKED,
        c.SQLITE_NOMEM => Error.SQLITE_NOMEM,
        c.SQLITE_READONLY => Error.SQLITE_READONLY,
        c.SQLITE_INTERRUPT => Error.SQLITE_INTERRUPT,
        c.SQLITE_IOERR => Error.SQLITE_IOERR,
        c.SQLITE_CORRUPT => Error.SQLITE_CORRUPT,
        c.SQLITE_NOTFOUND => Error.SQLITE_NOTFOUND,
        c.SQLITE_FULL => Error.SQLITE_FULL,
        c.SQLITE_CANTOPEN => Error.SQLITE_CANTOPEN,
        c.SQLITE_PROTOCOL => Error.SQLITE_PROTOCOL,
        c.SQLITE_EMPTY => Error.SQLITE_EMPTY,
        c.SQLITE_SCHEMA => Error.SQLITE_SCHEMA,
        c.SQLITE_TOOBIG => Error.SQLITE_TOOBIG,
        c.SQLITE_CONSTRAINT => Error.SQLITE_CONSTRAINT,
        c.SQLITE_MISMATCH => Error.SQLITE_MISMATCH,
        c.SQLITE_MISUSE => Error.SQLITE_MISUSE,
        c.SQLITE_NOLFS => Error.SQLITE_NOLFS,
        c.SQLITE_AUTH => Error.SQLITE_AUTH,
        c.SQLITE_FORMAT => Error.SQLITE_FORMAT,
        c.SQLITE_RANGE => Error.SQLITE_RANGE,
        c.SQLITE_NOTADB => Error.SQLITE_NOTADB,
        c.SQLITE_NOTICE => Error.SQLITE_NOTICE,
        c.SQLITE_WARNING => Error.SQLITE_WARNING,
        c.SQLITE_ROW => Error.SQLITE_ROW,
        c.SQLITE_DONE => Error.SQLITE_DONE,
        else => @panic("invalid error code"),
    };
}

pub fn throw(code: c_int) Error!void {
    return switch (code & 0xFF) {
        c.SQLITE_OK => {},
        else => getError(code),
    };
}
