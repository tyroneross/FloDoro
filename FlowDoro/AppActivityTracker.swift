import Foundation
import AppKit
import CSQLite

/// Tracks which applications the user is actively using.
/// Monitors the frontmost (active) application every 2 seconds.
/// Stores accumulated time per app in SQLite — completely local, no file content access.
@MainActor
final class AppActivityTracker: ObservableObject {
    static let shared = AppActivityTracker()

    /// Current active app info
    @Published private(set) var currentApp: String = ""
    @Published private(set) var currentAppBundleID: String = ""

    /// Today's usage summary — sorted by duration descending
    @Published private(set) var todaySummary: [AppUsageEntry] = []

    private var pollTimer: Timer?
    private var lastApp: String = ""
    private var lastBundleID: String = ""
    private var lastSwitchTime: Date = Date()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowDoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        dbPath = appDir.appendingPathComponent("activity.db").path

        openDatabase()
        createTable()
        startTracking()
    }

    deinit {
        sqlite3_close(db)
        pollTimer?.invalidate()
    }

    // MARK: - Database

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[FlowDoro Activity] DB open failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS app_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            date TEXT NOT NULL,
            hour INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_app_usage_date ON app_usage(date);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("[FlowDoro Activity] Table error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Tracking

    private func startTracking() {
        checkActiveApp() // initial
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkActiveApp()
            }
        }
    }

    private func checkActiveApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleID = frontApp.bundleIdentifier ?? "unknown"

        currentApp = appName
        currentAppBundleID = bundleID

        // If app changed, log the duration spent on the previous app
        if appName != lastApp && !lastApp.isEmpty {
            let duration = Int(Date().timeIntervalSince(lastSwitchTime))
            if duration >= 2 { // ignore sub-2s flickers
                recordUsage(appName: lastApp, bundleID: lastBundleID, durationSeconds: duration)
            }
            lastSwitchTime = Date()
        } else if lastApp.isEmpty {
            lastSwitchTime = Date()
        }

        lastApp = appName
        lastBundleID = bundleID
    }

    /// Flush the current app's accumulated time (call on timer completion or app pause)
    func flushCurrentApp() {
        guard !lastApp.isEmpty else { return }
        let duration = Int(Date().timeIntervalSince(lastSwitchTime))
        if duration >= 2 {
            recordUsage(appName: lastApp, bundleID: lastBundleID, durationSeconds: duration)
        }
        lastSwitchTime = Date()
    }

    private func recordUsage(appName: String, bundleID: String, durationSeconds: Int) {
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: now)
        let hour = Calendar.current.component(.hour, from: now)

        let sql = "INSERT INTO app_usage (app_name, bundle_id, duration_seconds, date, hour, created_at) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (appName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (bundleID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, Int32(durationSeconds))
        sqlite3_bind_text(stmt, 4, (dateStr as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 5, Int32(hour))
        sqlite3_bind_double(stmt, 6, now.timeIntervalSince1970)

        sqlite3_step(stmt)

        // Refresh today's summary
        refreshTodaySummary()
    }

    // MARK: - Query

    func refreshTodaySummary() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        let sql = "SELECT app_name, SUM(duration_seconds) as total FROM app_usage WHERE date = ? GROUP BY app_name ORDER BY total DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (today as NSString).utf8String, -1, nil)

        var results: [AppUsageEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let total = Int(sqlite3_column_int(stmt, 1))
            results.append(AppUsageEntry(appName: name, totalSeconds: total))
        }
        todaySummary = results
    }

    /// Get hourly breakdown for a specific date
    func hourlyBreakdown(date: String) -> [HourlyUsage] {
        let sql = "SELECT hour, app_name, SUM(duration_seconds) as total FROM app_usage WHERE date = ? GROUP BY hour, app_name ORDER BY hour, total DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)

        var results: [HourlyUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let total = Int(sqlite3_column_int(stmt, 2))
            results.append(HourlyUsage(hour: hour, appName: name, totalSeconds: total))
        }
        return results
    }
}

// MARK: - Data Types

struct AppUsageEntry: Identifiable {
    let id = UUID()
    let appName: String
    let totalSeconds: Int

    var formattedDuration: String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Percentage of total tracked time (set externally)
    var percentage: Double { 0 }
}

struct HourlyUsage: Identifiable {
    let id = UUID()
    let hour: Int
    let appName: String
    let totalSeconds: Int

    var hourLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date).lowercased()
        }
        return "\(hour):00"
    }
}
