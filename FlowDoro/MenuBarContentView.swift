import SwiftUI

/// Popover panel shown when clicking the menu bar item
struct MenuBarContentView: View {
    @ObservedObject var engine: TimerEngine

    private var colors: ModeColorSet {
        modeColors(for: engine.mode, isBreak: engine.isBreak)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Phase + mode header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(phaseIndicatorColor)
                        .frame(width: 8, height: 8)
                    Text(engine.phaseLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Text(engine.mode.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.bg))
            }

            // Time display
            Text(engine.displayTime)
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)

            // Warning indicator
            if engine.isApproachingEnd {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Ending soon")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color(red: 0.573, green: 0.251, blue: 0.055))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.warningYellow))
            }

            // Cycle counter
            if engine.completedCycles > 0 {
                Text("\(engine.completedCycles) cycle\(engine.completedCycles != 1 ? "s" : "") today")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

            Divider()

            // Quick controls
            HStack(spacing: 8) {
                Button {
                    engine.handleStart()
                } label: {
                    Text(mainButtonLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(colors.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mainButtonLabel)

                if engine.phase != .idle {
                    Button {
                        engine.handleReset()
                    } label: {
                        Text("Reset")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.borderLight, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset timer")
                }
            }

            // Flow stop
            if engine.isFlowType && engine.phase == .work && engine.isRunning {
                Button {
                    engine.handleFlowStop()
                } label: {
                    Text("Stop Flow")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.863, green: 0.149, blue: 0.149))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 1, green: 0.95, blue: 0.95))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.996, green: 0.792, blue: 0.792), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop flow session")
            }

            Divider()

            // Open main window
            Button {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.contentView != nil && !window.title.isEmpty {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11))
                    Text("Open FlowDoro")
                        .font(.system(size: 12))
                }
                .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open FlowDoro main window")
        }
        .padding(16)
        .frame(width: 260)
    }

    private var mainButtonLabel: String {
        if engine.phase == .idle { return "Start" }
        if engine.breakEnded { return "Next cycle" }
        return engine.isRunning ? "Pause" : "Resume"
    }

    private var phaseIndicatorColor: Color {
        switch engine.phase {
        case .idle: return .textTertiary
        case .work: return engine.isRunning ? colors.accent : .orange
        case .shortBreak, .longBreak: return .breakAccent
        }
    }
}
