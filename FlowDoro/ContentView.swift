import SwiftUI

struct ContentView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var activityTracker: AppActivityTracker = .shared
    @State private var showActivity: Bool = false
    @State private var showSettings: Bool = false
    @State private var showCustomize: Bool = false

    private var colors: ModeColorSet {
        modeColors(for: engine.mode, isBreak: engine.isBreak)
    }

    var body: some View {
        ZStack {
            ZStack {
                Color.bgPrimary
                Color.warningYellow.opacity(engine.warningIntensity)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.5), value: engine.warningIntensity)

            VStack(spacing: 0) {
                // Header
                headerView
                // Mode selector
                modeSelectorView
                // Mode info
                modeInfoView

                Spacer()

                // Phase label
                Text(engine.phaseLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(engine.phase == .idle ? .textTertiary : colors.accent)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.bottom, 10)

                // Timer ring
                TimerRingView(
                    progress: engine.progress,
                    accent: colors.accent,
                    displayTime: engine.displayTime,
                    subtitle: ringSubtitle,
                    isIdle: engine.phase == .idle
                )
                .padding(.bottom, 24)

                // Grace period
                if engine.graceActive {
                    graceView
                }

                // Controls
                controlsView

                // Cycle dots
                if engine.phase != .idle {
                    cycleDots
                }

                Spacer()

                // Footer
                footerView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Modals overlay
            if engine.showCheckIn, let data = engine.checkInData, engine.phase == .work {
                CheckInView(engine: engine, data: data)
            }

            if engine.showBreakRec, let rec = engine.recommendedBreak {
                BreakRecView(engine: engine, elapsed: engine.elapsed, recommendedBreak: rec)
            }

            if engine.showSignalCheck {
                SignalCheckView(engine: engine)
            }

            if engine.showLog {
                SessionLogView(engine: engine)
            }

            if showActivity {
                ActivityView(tracker: activityTracker, isPresented: $showActivity)
            }

            if showSettings {
                SettingsView(isPresented: $showSettings)
            }

            if showCustomize {
                CustomizeView(isPresented: $showCustomize)
            }

            // Escalation hint toast
            if engine.showEscalateHint, let hint = engine.mode.escalateHint {
                VStack {
                    escalateToast(hint)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(minWidth: 380, minHeight: 580)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FlowDoro")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)

                HStack(spacing: 4) {
                    Text("\(engine.completedCycles) cycle\(engine.completedCycles != 1 ? "s" : "")")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)

                    if let opt = engine.optimalWindow {
                        Text("· Optimal: ~\(opt)m")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.f1Accent)
                    } else if let avg = engine.avgFlowDuration {
                        Text("· Avg flow: ~\(avg)m")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.flowAccent)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    showActivity.toggle()
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("App activity")

                if !engine.sessionLog.isEmpty {
                    Button("Log (\(engine.sessionLog.count))") {
                        engine.showLog.toggle()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Session log, \(engine.sessionLog.count) entries")
                }
                if engine.phase != .idle {
                    Button("Reset") {
                        engine.handleReset()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Reset timer")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Mode Selector

    private var modeSelectorView: some View {
        HStack(spacing: 4) {
            ForEach(Array(ALL_MODES.enumerated()), id: \.element.id) { index, m in
                Button {
                    if engine.phase == .idle {
                        engine.selectedModeIndex = index
                    }
                } label: {
                    Text(m.label)
                        .font(.system(size: 12, weight: engine.selectedModeIndex == index ? .semibold : .regular))
                        .foregroundColor(engine.selectedModeIndex == index ? .textPrimary : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(engine.selectedModeIndex == index ? Color.white : Color.clear)
                                .shadow(color: engine.selectedModeIndex == index ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .opacity(engine.phase != .idle && engine.selectedModeIndex != index ? 0.35 : 1)
                .disabled(engine.phase != .idle)
                .accessibilityLabel("\(m.label) mode")
                .accessibilityAddTraits(engine.selectedModeIndex == index ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.surfaceLight))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Mode Info

    private var modeInfoView: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if engine.mode.id == "custom" {
                    let em = engine.effectiveMode
                    Text("\(em.work ?? 25):\(String(format: "%02d", em.breakMin ?? 5)) work/break")
                } else if let w = engine.mode.work, let b = engine.mode.breakMin {
                    Text("\(w):\(String(format: "%02d", b)) work/break")
                } else {
                    Text("Variable work/break")
                }
                if let cap = engine.mode.hardCap {
                    Text("· \(cap)m cap")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.textPrimary.opacity(0.85))

            Text(engine.mode.desc)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)

            if engine.mode.id == "custom" && engine.phase == .idle {
                Button("Customize") {
                    showCustomize = true
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.timerAccent)
                .padding(.top, 4)
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Ring Subtitle

    private var ringSubtitle: String {
        if engine.isFlowType && engine.phase == .work {
            return "\(engine.mode.hardCap ?? 90)m cap"
        } else if (engine.isBreak || engine.phase == .work) && engine.totalTime > 0 {
            return "of \(engine.totalTime / 60):00"
        }
        return ""
    }

    // MARK: - Grace View

    private var graceView: some View {
        VStack(spacing: 8) {
            Text("Finish your thought...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.amberText)

            Button("Done — take break") {
                engine.handleGraceDone()
            }
            .font(.system(size: 12))
            .foregroundColor(.amberText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(8)
            .accessibilityLabel("Finish and take a break")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        )
        .padding(.bottom, 14)
        .frame(maxWidth: 280)
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: 10) {
            // Main button
            Button {
                engine.handleStart()
            } label: {
                Text(mainButtonLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 36)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colors.accent)
                            .shadow(color: colors.shadow, radius: 6, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mainButtonLabel)

            // Flow stop
            if engine.isFlowType && engine.phase == .work && engine.isRunning {
                Button("Stop") {
                    engine.handleFlowStop()
                }
                .buttonStyle(DangerButtonStyle())
                .accessibilityLabel("Stop flow session")
            }

            // Skip work
            if engine.phase != .idle && !engine.isFlowType && !engine.graceActive && engine.phase == .work {
                Button("Skip →") {
                    engine.handleSkip()
                }
                .buttonStyle(MutedButtonStyle())
                .accessibilityLabel("Skip work phase")
            }

            // Skip break
            if engine.isBreak && !engine.breakEnded {
                Button("Skip break →") {
                    engine.handleSkip()
                }
                .buttonStyle(MutedButtonStyle())
                .accessibilityLabel("Skip break")
            }
        }
    }

    private var mainButtonLabel: String {
        if engine.phase == .idle { return "Start" }
        if engine.breakEnded { return "Next cycle" }
        return engine.isRunning ? "Pause" : "Resume"
    }

    // MARK: - Cycle Dots

    private var cycleDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<engine.mode.cyclesBeforeLong, id: \.self) { i in
                Circle()
                    .fill(i < (engine.completedCycles % engine.mode.cyclesBeforeLong) ? colors.accent : Color.borderLight)
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.3), value: engine.completedCycles)
            }
            Text("until long break")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .padding(.leading, 4)
        }
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle \(engine.completedCycles % engine.mode.cyclesBeforeLong) of \(engine.mode.cyclesBeforeLong) until long break")
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 2) {
            Text("BEST FOR")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .tracking(0.5)
            Text(engine.mode.best)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary.opacity(0.85))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 11).fill(colors.bg))
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Escalation Toast

    private func escalateToast(_ hint: String) -> some View {
        VStack(spacing: 4) {
            Text("💡 \(hint)")
                .font(.system(size: 13))
                .foregroundColor(.textPrimary.opacity(0.85))
            Button("Dismiss") {
                engine.showEscalateHint = false
            }
            .font(.system(size: 12))
            .foregroundColor(.textTertiary)
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderLight, lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - Button Styles

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color(red: 0.863, green: 0.149, blue: 0.149))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(red: 1, green: 0.95, blue: 0.95))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.996, green: 0.792, blue: 0.792), lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct MutedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(red: 0.953, green: 0.957, blue: 0.961))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
