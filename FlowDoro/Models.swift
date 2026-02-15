import Foundation

// MARK: - Work Modes

enum ModeType: String, Codable {
    case timer, flow, f1
}

struct WorkMode: Identifiable {
    let id: String
    let label: String
    let work: Int?          // minutes, nil = variable
    let breakMin: Int?      // minutes, nil = computed
    let longBreak: Int
    let cyclesBeforeLong: Int
    let desc: String
    let best: String
    let type: ModeType
    let hardCap: Int?       // minutes
    let escalateHint: String?

    var isFlowType: Bool { type == .flow || type == .f1 }
}

let ALL_MODES: [WorkMode] = [
    WorkMode(
        id: "micro", label: "Micro",
        work: 12, breakMin: 3, longBreak: 10, cyclesBeforeLong: 4,
        desc: "Energy preservation · Low activation",
        best: "Admin, email, light review, getting unstuck",
        type: .timer, hardCap: nil,
        escalateHint: "Attention stabilized? Try Pomodoro or Extended."
    ),
    WorkMode(
        id: "pomodoro", label: "Pomodoro",
        work: 25, breakMin: 5, longBreak: 15, cyclesBeforeLong: 4,
        desc: "Behavioral scaffold · Structure for drift",
        best: "Studying, drafting, task batching",
        type: .timer, hardCap: nil,
        escalateHint: "Overrunning the timer? Try Flow."
    ),
    WorkMode(
        id: "extended", label: "Extended",
        work: 50, breakMin: 12, longBreak: 20, cyclesBeforeLong: 3,
        desc: "Deep analytical · High ramp-up cost",
        best: "Strategy docs, coding, modeling, research",
        type: .timer, hardCap: nil,
        escalateHint: "Peaking before the timer? Try Flow."
    ),
    WorkMode(
        id: "flow", label: "Flow",
        work: nil, breakMin: nil, longBreak: 20, cyclesBeforeLong: 3,
        desc: "Adaptive · Check-ins guide your rhythm",
        best: "Design, synthesis, complex problem solving",
        type: .flow, hardCap: 90,
        escalateHint: nil
    ),
    WorkMode(
        id: "f1", label: "F1 ★",
        work: nil, breakMin: nil, longBreak: 25, cyclesBeforeLong: 2,
        desc: "Signal-based · Discovers your optimal window",
        best: "High-stakes deep work, finding your rhythm",
        type: .f1, hardCap: 90,
        escalateHint: nil
    ),
]

// MARK: - Decay Signals

struct DecaySignal: Identifiable {
    let id: String
    let label: String
    let icon: String
}

let DECAY_SIGNALS: [DecaySignal] = [
    DecaySignal(id: "re-reading", label: "Re-reading without progress", icon: "📖"),
    DecaySignal(id: "slow-decisions", label: "Decisions getting slower", icon: "🐌"),
    DecaySignal(id: "small-errors", label: "Making small errors", icon: "✏️"),
    DecaySignal(id: "task-drift", label: "Drifting to other tasks", icon: "🌊"),
]

// MARK: - Session Entry

struct SessionEntry: Identifiable, Codable {
    let id: UUID
    let mode: String
    let focusSeconds: Int
    let focusMinutes: Int
    let stopReason: String
    let signals: [String]?
    let timestamp: String
    let date: String
    let createdAt: Date

    /// Approximate start time of this session
    var startedAt: Date {
        createdAt.addingTimeInterval(-Double(focusSeconds))
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        return df
    }()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    /// Convenience init for new sessions (sets createdAt = now)
    init(mode: String, focusSeconds: Int, stopReason: String, signals: [String]? = nil) {
        self.id = UUID()
        self.mode = mode
        self.focusSeconds = focusSeconds
        self.focusMinutes = Int(round(Double(focusSeconds) / 60.0))
        self.stopReason = stopReason
        self.signals = signals
        self.createdAt = Date()

        let now = Date()
        self.date = Self.dateFormatter.string(from: now)
        self.timestamp = Self.timeFormatter.string(from: now)
    }

    /// Full-fidelity init for database hydration — preserves all stored fields
    init(id: UUID, mode: String, focusSeconds: Int, focusMinutes: Int,
         stopReason: String, signals: [String]?, timestamp: String,
         date: String, createdAt: Date) {
        self.id = id
        self.mode = mode
        self.focusSeconds = focusSeconds
        self.focusMinutes = focusMinutes
        self.stopReason = stopReason
        self.signals = signals
        self.timestamp = timestamp
        self.date = date
        self.createdAt = createdAt
    }
}

// MARK: - Check-In

struct CheckInData {
    let level: CheckInLevel
    let message: String
}

enum CheckInLevel: String {
    case gentle, moderate, firm, strong, urgent
}

// MARK: - Phase

enum TimerPhase: String {
    case idle, work, shortBreak, longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

// MARK: - Helpers

func computeBreak(focusSeconds: Int) -> Int {
    let focusMin = Double(focusSeconds) / 60.0
    let raw = Int(round(focusMin / 5.0))
    return max(5, min(20, raw))
}

func getCheckInSchedule(elapsedSeconds: Int) -> CheckInData? {
    let min = Double(elapsedSeconds) / 60.0
    guard min >= 35 else { return nil }

    let intervals: [(Double, CheckInLevel, String)] = [
        (35, .gentle, "Quick check — still in the zone?"),
        (50, .moderate, "You've been at it a while. Consider a break soon."),
        (65, .firm, "Over an hour in. A break will sharpen your next stretch."),
        (75, .strong, "Diminishing returns likely. Seriously consider stopping."),
        (85, .urgent, "Hard cap approaching. Break strongly recommended."),
    ]

    for (t, level, message) in intervals {
        if abs(min - t) < 0.6 {
            return CheckInData(level: level, message: message)
        }
    }
    return nil
}

func formatTime(_ totalSeconds: Int) -> String {
    let m = totalSeconds / 60
    let s = totalSeconds % 60
    return String(format: "%02d:%02d", m, s)
}
