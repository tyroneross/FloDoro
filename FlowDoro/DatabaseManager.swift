import Foundation
import CSQLite
import os.log

/// Local-only SQLite database for session persistence.
/// No network calls. Data stays on disk at ~/Library/Application Support/FlowDoro/sessions.db
final class DatabaseManager {
    static let shared = DatabaseManager()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro", category: "database")

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Self.logger.fault("Unable to locate Application Support directory")
            dbPath = ""
            return
        }
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
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Self.logger.error("Failed to open database at \(self.dbPath, privacy: .public): \(errMsg, privacy: .public)")
        }
        // Enable WAL mode for better concurrency and crash safety
        var walErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, &walErr)
        if let walErr = walErr {
            Self.logger.warning("WAL mode error: \(String(cString: walErr), privacy: .public)")
            sqlite3_free(walErr)
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
                Self.logger.error("Table creation error: \(String(cString: errMsg), privacy: .public)")
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
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Self.logger.error("Insert prepare failed: \(errMsg, privacy: .public)")
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
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Self.logger.error("Insert failed: \(errMsg, privacy: .public)")
        }
    }

    // MARK: - Query

    func fetchAllSessions() -> [SessionEntry] {
        let sql = "SELECT id, mode, focus_seconds, focus_minutes, stop_reason, signals, timestamp, date, created_at FROM sessions ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Self.logger.error("Fetch prepare failed: \(errMsg, privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [SessionEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let modePtr = sqlite3_column_text(stmt, 1),
                  let reasonPtr = sqlite3_column_text(stmt, 4) else {
                continue
            }
            let mode = String(cString: modePtr)
            let focusSeconds = Int(sqlite3_column_int(stmt, 2))
            let stopReason = String(cString: reasonPtr)

            var signals: [String]?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL, let sigPtr = sqlite3_column_text(stmt, 5) {
                let raw = String(cString: sigPtr)
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
                Self.logger.error("Delete error: \(String(cString: errMsg), privacy: .public)")
                sqlite3_free(errMsg)
            }
        }
    }

    /// Get the database file path (for debugging)
    var databasePath: String { dbPath }
}
