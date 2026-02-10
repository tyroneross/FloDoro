import SwiftUI

/// The label shown in the macOS system menu bar — phase icon + countdown
struct MenuBarLabel: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: phaseIcon)
                .font(.system(size: 11))
            Text(menuBarText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
    }

    private var phaseIcon: String {
        switch engine.phase {
        case .idle:
            return "timer"
        case .work:
            switch engine.mode.type {
            case .f1: return "sparkles"
            case .flow: return "wind"
            case .timer: return "brain.head.profile"
            }
        case .shortBreak:
            return "cup.and.saucer"
        case .longBreak:
            return "cup.and.saucer.fill"
        }
    }

    private var menuBarText: String {
        switch engine.phase {
        case .idle:
            return "Ready"
        case .work:
            if engine.isFlowType {
                return formatTime(engine.elapsed)
            }
            return formatTime(engine.timeLeft)
        case .shortBreak, .longBreak:
            return formatTime(engine.timeLeft)
        }
    }
}
