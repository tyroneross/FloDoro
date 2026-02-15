import Foundation
import SwiftData

// MARK: - SwiftData Models (CloudKit-Compatible)
//
// Rules for CloudKit compatibility:
// - No @Attribute(.unique) — CloudKit doesn't support uniqueness constraints
// - All properties optional or defaulted — non-optional without defaults silently fail sync
// - All relationships optional, no .deny delete rules
// - Schema changes must be lightweight migrations only

/// A completed focus session, synced across all devices via iCloud.
@Model
final class FocusSession {
    var id: UUID = UUID()
    var mode: String = "timer"           // WorkMode.id: "micro", "pomodoro", "extended", "flow", "f1"
    var modeLabel: String = ""           // WorkMode.label: "Micro", "Pomodoro", etc.
    var focusSeconds: Int = 0
    var focusMinutes: Int = 0
    var stopReason: String = "manual"    // "timer", "manual", "hard-cap", "decay-signals", "timer+grace", "skipped"
    var signals: String?                 // Comma-separated F1 decay signals (nil for non-F1 modes)
    var sessionDate: String = ""         // ISO date: "2026-02-11"
    var sessionTime: String = ""         // Localized time string: "2:30 PM"
    var createdAt: Date = Date()
    var deviceID: String = ""            // Stable per-device identifier
    var deviceType: String = ""          // "mac", "iphone", "ipad", "watch"

    init() {}

    /// Convenience init from legacy SessionEntry
    convenience init(from entry: SessionEntry, deviceID: String, deviceType: String) {
        self.init()
        self.id = entry.id
        self.mode = entry.mode
        self.modeLabel = ALL_MODES.first(where: { $0.id == entry.mode })?.label ?? entry.mode
        self.focusSeconds = entry.focusSeconds
        self.focusMinutes = entry.focusMinutes
        self.stopReason = entry.stopReason
        self.signals = entry.signals?.joined(separator: ",")
        self.sessionDate = entry.date
        self.sessionTime = entry.timestamp
        self.createdAt = entry.createdAt
        self.deviceID = deviceID
        self.deviceType = deviceType
    }

    /// Convert back to SessionEntry for compatibility with existing TimerEngine
    func toSessionEntry() -> SessionEntry {
        return SessionEntry(
            id: id,
            mode: mode,
            focusSeconds: focusSeconds,
            focusMinutes: focusMinutes,
            stopReason: stopReason,
            signals: signals?.components(separatedBy: ",").filter { !$0.isEmpty },
            timestamp: sessionTime,
            date: sessionDate,
            createdAt: createdAt
        )
    }
}

/// App usage record, synced across devices.
/// macOS: populated via NSWorkspace polling
/// iOS: populated via Screen Time API (DeviceActivity framework)
/// watchOS: not populated (no app usage tracking on watch)
@Model
final class AppUsageRecord {
    var id: UUID = UUID()
    var appName: String = ""
    var bundleID: String = ""
    var durationSeconds: Int = 0
    var usageDate: String = ""           // ISO date: "2026-02-11"
    var hour: Int = 0                    // 0-23
    var createdAt: Date = Date()
    var source: String = ""              // "nsworkspace" (Mac), "screentime" (iOS)
    var deviceID: String = ""

    init() {}
}

/// User preferences, synced across devices. Last-write-wins on conflict.
@Model
final class UserPreferences {
    var id: UUID = UUID()
    var preferredMode: String = "pomodoro"   // Default mode ID
    var lastUpdated: Date = Date()
    var deviceID: String = ""                // Which device last changed this

    init() {}
}

// MARK: - Sync Message Types

/// Lightweight message for real-time timer state sync (Network Framework / Watch Connectivity).
/// NOT persisted — this is ephemeral state broadcast between nearby devices.
struct TimerStateMessage: Codable {
    let deviceID: String
    let deviceType: String
    let phase: String            // TimerPhase.rawValue
    let mode: String             // WorkMode.id
    let elapsed: Int
    let timeLeft: Int
    let totalTime: Int
    let isRunning: Bool
    let timestamp: Date

    var asDictionary: [String: Any] {
        [
            "deviceID": deviceID,
            "deviceType": deviceType,
            "phase": phase,
            "mode": mode,
            "elapsed": elapsed,
            "timeLeft": timeLeft,
            "totalTime": totalTime,
            "isRunning": isRunning,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }

    init(deviceID: String, deviceType: String, phase: String, mode: String,
         elapsed: Int, timeLeft: Int, totalTime: Int, isRunning: Bool) {
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.phase = phase
        self.mode = mode
        self.elapsed = elapsed
        self.timeLeft = timeLeft
        self.totalTime = totalTime
        self.isRunning = isRunning
        self.timestamp = Date()
    }

    init?(from dictionary: [String: Any]) {
        guard let deviceID = dictionary["deviceID"] as? String,
              let deviceType = dictionary["deviceType"] as? String,
              let phase = dictionary["phase"] as? String,
              let mode = dictionary["mode"] as? String,
              let elapsed = dictionary["elapsed"] as? Int,
              let timeLeft = dictionary["timeLeft"] as? Int,
              let totalTime = dictionary["totalTime"] as? Int,
              let isRunning = dictionary["isRunning"] as? Bool,
              let ts = dictionary["timestamp"] as? TimeInterval else {
            return nil
        }
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.phase = phase
        self.mode = mode
        self.elapsed = elapsed
        self.timeLeft = timeLeft
        self.totalTime = totalTime
        self.isRunning = isRunning
        self.timestamp = Date(timeIntervalSince1970: ts)
    }
}

/// Lightweight session completion event for real-time broadcast.
struct SessionCompleteMessage: Codable {
    let sessionID: UUID
    let deviceID: String
    let mode: String
    let focusMinutes: Int
    let stopReason: String
    let timestamp: Date

    var asDictionary: [String: Any] {
        [
            "type": "sessionComplete",
            "sessionID": sessionID.uuidString,
            "deviceID": deviceID,
            "mode": mode,
            "focusMinutes": focusMinutes,
            "stopReason": stopReason,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }
}
