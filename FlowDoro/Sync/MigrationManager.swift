import Foundation
import SwiftData
import os.log

#if canImport(CSQLite)
import CSQLite
#endif

// MARK: - Legacy Migration Manager
//
// One-time migration from the existing SQLite databases (sessions.db, activity.db)
// to SwiftData. Runs on first launch of the new version.
//
// After migration:
// - All historical sessions appear in SwiftData (and sync to iCloud)
// - iPhone and Watch receive the data via CloudKit automatically
// - SQLite databases are kept as backup but no longer written to
//
// Migration is idempotent — safe to run multiple times.

struct MigrationManager {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro",
        category: "migration"
    )

    private static let migrationKey = "flodoro.migration.sqlite_to_swiftdata_completed"
    private static let activityMigrationKey = "flodoro.migration.activity_completed"

    // MARK: - Public API

    /// Run all pending migrations. Call once on app launch.
    @MainActor
    static func migrateIfNeeded(container: ModelContainer) {
        migrateSessionsIfNeeded(container: container)
        migrateActivityIfNeeded(container: container)
    }

    // MARK: - Session Migration

    @MainActor
    private static func migrateSessionsIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return // Already migrated
        }

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            logger.warning("Cannot locate Application Support directory")
            return
        }

        let dbPath = appSupport
            .appendingPathComponent("FlowDoro")
            .appendingPathComponent("sessions.db")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            logger.info("No legacy sessions.db found — skipping migration")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        logger.info("Starting session migration from SQLite to SwiftData")

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            logger.error("Failed to open legacy sessions.db for migration")
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, mode, focus_seconds, focus_minutes, stop_reason, signals, timestamp, date, created_at
        FROM sessions ORDER BY created_at ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare migration query")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let context = container.mainContext
        var migratedCount = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            let session = FocusSession()

            if let idPtr = sqlite3_column_text(stmt, 0) {
                session.id = UUID(uuidString: String(cString: idPtr)) ?? UUID()
            }
            if let modePtr = sqlite3_column_text(stmt, 1) {
                session.mode = String(cString: modePtr)
                session.modeLabel = ALL_MODES.first(where: { $0.id == session.mode })?.label ?? session.mode
            }

            session.focusSeconds = Int(sqlite3_column_int(stmt, 2))
            session.focusMinutes = Int(sqlite3_column_int(stmt, 3))

            if let reasonPtr = sqlite3_column_text(stmt, 4) {
                session.stopReason = String(cString: reasonPtr)
            }

            if sqlite3_column_type(stmt, 5) != SQLITE_NULL, let sigPtr = sqlite3_column_text(stmt, 5) {
                let raw = String(cString: sigPtr)
                if !raw.isEmpty {
                    session.signals = raw  // Already comma-separated in SQLite
                }
            }

            if let timePtr = sqlite3_column_text(stmt, 6) {
                session.sessionTime = String(cString: timePtr)
            }
            if let datePtr = sqlite3_column_text(stmt, 7) {
                session.sessionDate = String(cString: datePtr)
            }

            let createdAtTimestamp = sqlite3_column_double(stmt, 8)
            session.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)

            // Tag as migrated from Mac (since this is the only platform with legacy data)
            session.deviceID = DeviceIdentifier.current
            session.deviceType = "mac"

            context.insert(session)
            migratedCount += 1
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.info("Session migration complete: \(migratedCount) sessions migrated")
        } catch {
            logger.error("Failed to save migrated sessions: \(error.localizedDescription)")
        }
    }

    // MARK: - Activity Migration

    @MainActor
    private static func migrateActivityIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: activityMigrationKey) else {
            return
        }

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }

        let dbPath = appSupport
            .appendingPathComponent("FlowDoro")
            .appendingPathComponent("activity.db")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            UserDefaults.standard.set(true, forKey: activityMigrationKey)
            return
        }

        logger.info("Starting activity migration from SQLite to SwiftData")

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            logger.error("Failed to open legacy activity.db for migration")
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT app_name, bundle_id, duration_seconds, date, hour, created_at
        FROM app_usage ORDER BY created_at ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare activity migration query")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let context = container.mainContext
        var migratedCount = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            let record = AppUsageRecord()

            if let namePtr = sqlite3_column_text(stmt, 0) {
                record.appName = String(cString: namePtr)
            }
            if let bundlePtr = sqlite3_column_text(stmt, 1) {
                record.bundleID = String(cString: bundlePtr)
            }

            record.durationSeconds = Int(sqlite3_column_int(stmt, 2))

            if let datePtr = sqlite3_column_text(stmt, 3) {
                record.usageDate = String(cString: datePtr)
            }

            record.hour = Int(sqlite3_column_int(stmt, 4))

            let createdAtTimestamp = sqlite3_column_double(stmt, 5)
            record.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)

            record.source = "nsworkspace"
            record.deviceID = DeviceIdentifier.current

            context.insert(record)
            migratedCount += 1
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: activityMigrationKey)
            logger.info("Activity migration complete: \(migratedCount) records migrated")
        } catch {
            logger.error("Failed to save migrated activity: \(error.localizedDescription)")
        }
    }
}
