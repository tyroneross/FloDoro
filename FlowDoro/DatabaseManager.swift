import Foundation
import CSQLite

/// Local-only SQLite database for session persistence.
/// No network calls. Data stays on disk at ~/Library/Application Support/FlowDoro/sessions.db
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowDoro", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        dbPath = appDir.appendingPathComponent("sessions.db").path
        openDatabase()
        createTable()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Connection

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[FlowDoro DB] Failed to open database at \(dbPath)")
            print("[FlowDoro DB] Error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            mode TEXT NOT NULL,
            focus_seconds INTEGER NOT NULL,
            focus_minutes INTEGER NOT NULL,
            stop_reason TEXT NOT NULL,
            signals TEXT,
            timestamp TEXT NOT NULL,
            date TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("[FlowDoro DB] Table creation error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Insert

    func insertSession(_ entry: SessionEntry) {
        let sql = """
        INSERT INTO sessions (id, mode, focus_seconds, focus_minutes, stop_reason, signals, timestamp, date, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[FlowDoro DB] Insert prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (entry.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (entry.mode as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, Int32(entry.focusSeconds))
        sqlite3_bind_int(stmt, 4, Int32(entry.focusMinutes))
        sqlite3_bind_text(stmt, 5, (entry.stopReason as NSString).utf8String, -1, nil)

        if let signals = entry.signals {
            let joined = signals.joined(separator: ",")
            sqlite3_bind_text(stmt, 6, (joined as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        sqlite3_bind_text(stmt, 7, (entry.timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (entry.date as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 9, entry.createdAt.timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[FlowDoro DB] Insert failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    // MARK: - Query

    func fetchAllSessions() -> [SessionEntry] {
        let sql = "SELECT id, mode, focus_seconds, focus_minutes, stop_reason, signals, timestamp, date, created_at FROM sessions ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[FlowDoro DB] Fetch prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [SessionEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let mode = String(cString: sqlite3_column_text(stmt, 1))
            let focusSeconds = Int(sqlite3_column_int(stmt, 2))
            let stopReason = String(cString: sqlite3_column_text(stmt, 4))

            var signals: [String]?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                let raw = String(cString: sqlite3_column_text(stmt, 5))
                if !raw.isEmpty {
                    signals = raw.components(separatedBy: ",")
                }
            }

            let entry = SessionEntry(
                mode: mode,
                focusSeconds: focusSeconds,
                stopReason: stopReason,
                signals: signals
            )
            results.append(entry)
        }
        return results
    }

    /// Sessions from today only
    func fetchTodaySessions() -> [SessionEntry] {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        return fetchAllSessions().filter { $0.date == today }
    }

    /// Delete all sessions (for reset)
    func deleteAllSessions() {
        let sql = "DELETE FROM sessions;"
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("[FlowDoro DB] Delete error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    /// Get the database file path (for debugging)
    var databasePath: String { dbPath }
}
