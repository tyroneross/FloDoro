import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Base
    static let bgPrimary = Color(red: 0.98, green: 0.98, blue: 0.98)
    static let textPrimary = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let textSecondary = Color(red: 0.42, green: 0.45, blue: 0.49)
    static let textTertiary = Color(red: 0.61, green: 0.64, blue: 0.69)
    static let borderLight = Color(red: 0.9, green: 0.91, blue: 0.91)
    static let surfaceLight = Color(red: 0.94, green: 0.94, blue: 0.94)
    static let cardBg = Color(red: 0.976, green: 0.98, blue: 0.984)
    static let warningYellow = Color(red: 1.0, green: 0.95, blue: 0.78)

    // Mode accents
    static let timerAccent = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let flowAccent = Color(red: 0.031, green: 0.569, blue: 0.698)
    static let f1Accent = Color(red: 0.486, green: 0.227, blue: 0.929)
    static let breakAccent = Color(red: 0.02, green: 0.588, blue: 0.412)

    // Check-in levels
    static let levelGentle = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let levelModerate = Color(red: 0.031, green: 0.569, blue: 0.698)
    static let levelFirm = Color(red: 0.851, green: 0.475, blue: 0.024)
    static let levelStrong = Color(red: 0.918, green: 0.345, blue: 0.047)
    static let levelUrgent = Color(red: 0.863, green: 0.149, blue: 0.149)

    // Amber (grace)
    static let amberText = Color(red: 0.573, green: 0.251, blue: 0.055)

    // Purple
    static let purpleText = Color(red: 0.357, green: 0.129, blue: 0.714)
}

// MARK: - Mode Color Set

struct ModeColorSet {
    let accent: Color
    let shadow: Color
    let bg: Color
}

func modeColors(for mode: WorkMode, isBreak: Bool) -> ModeColorSet {
    if isBreak {
        return ModeColorSet(accent: .breakAccent, shadow: .breakAccent.opacity(0.2), bg: .breakAccent.opacity(0.06))
    }
    switch mode.type {
    case .timer:
        return ModeColorSet(accent: .timerAccent, shadow: .timerAccent.opacity(0.2), bg: .timerAccent.opacity(0.06))
    case .flow:
        return ModeColorSet(accent: .flowAccent, shadow: .flowAccent.opacity(0.2), bg: .flowAccent.opacity(0.06))
    case .adaptive:
        return ModeColorSet(accent: .f1Accent, shadow: .f1Accent.opacity(0.2), bg: .f1Accent.opacity(0.06))
    }
}

func checkInAccentColor(for level: CheckInLevel) -> Color {
    switch level {
    case .gentle: return .levelGentle
    case .moderate: return .levelModerate
    case .firm: return .levelFirm
    case .strong: return .levelStrong
    case .urgent: return .levelUrgent
    }
}
