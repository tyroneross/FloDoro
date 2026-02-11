import Foundation
import SwiftData
import CloudKit
import os.log

// MARK: - Cloud Sync Manager
//
// Orchestrates all sync layers for FloDoro:
//
// Layer 1: SwiftData + CloudKit (automatic iCloud sync, ~15s latency)
//   - All FocusSessions, AppUsageRecords, UserPreferences sync via iCloud private database
//   - Zero code needed beyond ModelConfiguration(cloudKitDatabase: .automatic)
//   - Works across networks, handles offline gracefully
//
// Layer 2: Network Framework / Bonjour (same WiFi, <1s) — see LocalNetworkSync.swift
//   - Real-time timer state broadcast between Mac and iPhone
//
// Layer 3: Watch Connectivity (iPhone ↔ Watch, <1s) — see WatchSyncManager.swift
//   - Real-time timer state via sendMessage()
//   - Session records via transferUserInfo()
//
// This manager owns the ModelContainer and provides the single source of truth
// for SwiftData across the app.

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro",
        category: "sync"
    )

    /// The shared ModelContainer for all SwiftData operations.
    /// Configured with CloudKit sync when iCloud is available.
    let modelContainer: ModelContainer

    /// Whether iCloud sync is active
    @Published private(set) var iCloudSyncEnabled: Bool = false

    /// Last sync event (for UI status indicator)
    @Published private(set) var lastSyncDate: Date?

    private init() {
        let schema = Schema([
            FocusSession.self,
            AppUsageRecord.self,
            UserPreferences.self
        ])

        // Try CloudKit-enabled config first, fall back to local-only
        let config: ModelConfiguration
        do {
            config = ModelConfiguration(
                "FloDoro",
                schema: schema,
                cloudKitDatabase: .automatic  // Enables iCloud sync
            )
            iCloudSyncEnabled = true
            Self.logger.info("ModelContainer configured with CloudKit sync")
        } catch {
            // This path shouldn't be hit since ModelConfiguration init doesn't throw,
            // but defensive coding for future API changes
            config = ModelConfiguration(
                "FloDoro",
                schema: schema,
                cloudKitDatabase: .none
            )
            Self.logger.warning("CloudKit unavailable, using local-only storage")
        }

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fatal: if we can't create the container, the app can't store data
            Self.logger.fault("Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Session Operations

    /// Save a new focus session to SwiftData (auto-syncs via CloudKit)
    func saveSession(_ entry: SessionEntry) {
        let context = modelContainer.mainContext
        let session = FocusSession(
            from: entry,
            deviceID: DeviceIdentifier.current,
            deviceType: DeviceIdentifier.deviceType
        )
        context.insert(session)

        do {
            try context.save()
            lastSyncDate = Date()
            Self.logger.info("Session saved: \(entry.mode) \(entry.focusMinutes)m")
        } catch {
            Self.logger.error("Failed to save session: \(error.localizedDescription)")
        }
    }

    /// Fetch all sessions, sorted by creation date
    func fetchAllSessions() -> [FocusSession] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch sessions: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch today's sessions only
    func fetchTodaySessions() -> [FocusSession] {
        let todayStr = ISO8601DateFormatter.dateOnly.string(from: Date())
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.sessionDate == todayStr },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch today's sessions: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch sessions by device type (e.g., see all Watch sessions)
    func fetchSessions(deviceType: String) -> [FocusSession] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.deviceType == deviceType },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch sessions for \(deviceType): \(error.localizedDescription)")
            return []
        }
    }

    /// Delete all sessions (for reset)
    func deleteAllSessions() {
        let context = modelContainer.mainContext
        do {
            try context.delete(model: FocusSession.self)
            try context.save()
            Self.logger.info("All sessions deleted")
        } catch {
            Self.logger.error("Failed to delete sessions: \(error.localizedDescription)")
        }
    }

    // MARK: - App Usage Operations

    /// Save an app usage record
    func saveAppUsage(appName: String, bundleID: String, durationSeconds: Int,
                      date: String, hour: Int, source: String) {
        let context = modelContainer.mainContext
        let record = AppUsageRecord()
        record.appName = appName
        record.bundleID = bundleID
        record.durationSeconds = durationSeconds
        record.usageDate = date
        record.hour = hour
        record.source = source
        record.deviceID = DeviceIdentifier.current
        context.insert(record)

        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to save app usage: \(error.localizedDescription)")
        }
    }

    /// Fetch today's app usage summary grouped by app name
    func fetchTodayAppUsage() -> [(appName: String, totalSeconds: Int)] {
        let todayStr = ISO8601DateFormatter.dateOnly.string(from: Date())
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.usageDate == todayStr }
        )
        do {
            let records = try context.fetch(descriptor)
            // Group by app name and sum durations
            var grouped: [String: Int] = [:]
            for record in records {
                grouped[record.appName, default: 0] += record.durationSeconds
            }
            return grouped.map { (appName: $0.key, totalSeconds: $0.value) }
                .sorted { $0.totalSeconds > $1.totalSeconds }
        } catch {
            Self.logger.error("Failed to fetch app usage: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Preferences

    /// Get or create the user's preferences
    func getPreferences() -> UserPreferences {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<UserPreferences>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        do {
            let existing = try context.fetch(descriptor)
            if let prefs = existing.first {
                return prefs
            }
        } catch {
            Self.logger.error("Failed to fetch preferences: \(error.localizedDescription)")
        }

        // Create default preferences
        let prefs = UserPreferences()
        prefs.deviceID = DeviceIdentifier.current
        context.insert(prefs)
        try? context.save()
        return prefs
    }

    /// Update preferred mode
    func updatePreferredMode(_ modeID: String) {
        let prefs = getPreferences()
        prefs.preferredMode = modeID
        prefs.lastUpdated = Date()
        prefs.deviceID = DeviceIdentifier.current
        try? modelContainer.mainContext.save()
    }
}

// MARK: - ISO8601 Date Formatter Extension

extension ISO8601DateFormatter {
    /// Date-only formatter for session date strings (e.g., "2026-02-11")
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }()
}
