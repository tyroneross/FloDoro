import Foundation
import Combine
import AppKit

/// Core timer engine — drives all mode logic, check-ins, grace periods, and session logging.
/// Published properties drive SwiftUI reactivity.
@MainActor
final class TimerEngine: ObservableObject {

    // MARK: - Published State

    @Published var selectedModeIndex: Int = 1
    @Published var phase: TimerPhase = .idle
    @Published var timeLeft: Int = 0
    @Published var totalTime: Int = 0
    @Published var elapsed: Int = 0
    @Published var completedCycles: Int = 0
    @Published var isRunning: Bool = false

    // Check-in / signal
    @Published var showCheckIn: Bool = false
    @Published var checkInData: CheckInData?
    @Published var showSignalCheck: Bool = false
    @Published var selectedSignals: Set<String> = []

    // Break recommendation
    @Published var recommendedBreak: Int?
    @Published var showBreakRec: Bool = false

    // Session log
    @Published var sessionLog: [SessionEntry] = []
    @Published var showLog: Bool = false

    // Hints
    @Published var showEscalateHint: Bool = false
    @Published var graceActive: Bool = false

    // Mode switch guard — allows switching within 60s of starting, locks after
    @Published var showModeSwitchConfirm: Bool = false
    @Published var pendingModeIndex: Int?
    private var workStartedAt: Date?

    /// True when the timer is in a work phase and the 60-second grace window has expired.
    /// Breaks are never locked — switching during a break is always allowed.
    var isModeSwitchLocked: Bool {
        guard phase != .idle else { return false }
        guard !phase.isBreak else { return false }
        guard let started = workStartedAt else { return true }
        return Date().timeIntervalSince(started) >= 60
    }

    // MARK: - Computed

    var mode: WorkMode { ALL_MODES[selectedModeIndex] }
    var isFlowType: Bool { mode.isFlowType }
    var isBreak: Bool { phase.isBreak }
    var breakEnded: Bool { isBreak && timeLeft == 0 && totalTime > 0 }

    /// True when ≤2 minutes remain (timer work, breaks, or flow near hard cap)
    var isApproachingEnd: Bool {
        if phase == .work && !isFlowType && timeLeft > 0 && timeLeft <= 120 { return true }
        if phase == .work && isFlowType, let cap = mode.hardCap {
            let remaining = (cap * 60) - elapsed
            return remaining > 0 && remaining <= 120
        }
        if phase.isBreak && timeLeft > 0 && timeLeft <= 120 { return true }
        return false
    }

    /// 0.0 (just entered 2-min zone) → 1.0 (time is up) for smooth yellow fade
    var warningIntensity: Double {
        guard isApproachingEnd else { return 0 }
        if phase == .work && isFlowType, let cap = mode.hardCap {
            let remaining = Double((cap * 60) - elapsed)
            return max(0, min(1, 1.0 - (remaining / 120.0)))
        }
        return max(0, min(1, 1.0 - (Double(timeLeft) / 120.0)))
    }

    var progress: Double {
        if !isFlowType && totalTime > 0 && phase == .work {
            return Double(totalTime - timeLeft) / Double(totalTime)
        } else if isFlowType && phase == .work, let cap = mode.hardCap {
            return Double(elapsed) / Double(cap * 60)
        } else if isBreak && totalTime > 0 {
            return Double(totalTime - timeLeft) / Double(totalTime)
        }
        return 0
    }

    var phaseLabel: String {
        switch phase {
        case .idle: return "Ready"
        case .work:
            switch mode.type {
            case .f1: return "Discovering"
            case .flow: return "Flowing"
            case .timer: return "Focus"
            }
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var displayTime: String {
        switch phase {
        case .idle:
            if let w = mode.work { return formatTime(w * 60) }
            return "—:—"
        case .work:
            return isFlowType ? formatTime(elapsed) : formatTime(timeLeft)
        case .shortBreak, .longBreak:
            return formatTime(timeLeft)
        }
    }

    // Analytics
    var f1Sessions: [SessionEntry] {
        sessionLog.filter { $0.mode == "f1" && $0.focusMinutes > 0 }
    }
    var flowSessions: [SessionEntry] {
        sessionLog.filter { ($0.mode == "flow" || $0.mode == "f1") && $0.focusMinutes > 0 }
    }
    var optimalWindow: Int? {
        guard f1Sessions.count >= 3 else { return nil }
        let sorted = f1Sessions.map(\.focusMinutes).sorted()
        return sorted[sorted.count / 2]
    }
    var avgFlowDuration: Int? {
        guard flowSessions.count >= 2 else { return nil }
        let total = flowSessions.reduce(0) { $0 + $1.focusMinutes }
        return total / flowSessions.count
    }

    // MARK: - Private

    private var timer: Timer?
    private var graceTimer: Timer?
    private var lastCheckInMinute: Int = -1
    private var escalateTimer: Timer?

    // MARK: - Init

    init() {
        sessionLog = DatabaseManager.shared.fetchAllSessions()
    }

    // MARK: - Tick

    private func startTick() {
        stopTick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTick() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning else { return }

        if isFlowType && phase == .work {
            elapsed += 1
            if let cap = mode.hardCap, elapsed >= cap * 60 {
                stopTick()
                isRunning = false
                notifyCompletion(completedPhase: .work)
                handleWorkComplete(stopReason: "hard-cap", signals: [])
                return
            }
            checkFlowCheckIn()
        } else if phase == .work && !isFlowType {
            if timeLeft <= 1 {
                timeLeft = 0
                stopTick()
                isRunning = false
                notifyCompletion(completedPhase: .work)
                if mode.id == "pomodoro" {
                    startGracePeriod()
                } else {
                    handleWorkComplete(stopReason: "timer")
                }
                return
            }
            timeLeft -= 1
            elapsed += 1
        } else if isBreak {
            if timeLeft <= 1 {
                timeLeft = 0
                stopTick()
                isRunning = false
                showBreakRec = false
                notifyCompletion(completedPhase: phase)
                return
            }
            timeLeft -= 1
        }
    }

    // MARK: - Flow Check-Ins

    private let checkPoints = [35, 50, 65, 75, 85]

    private func checkFlowCheckIn() {
        let min = elapsed / 60
        for cp in checkPoints {
            if min == cp && lastCheckInMinute != cp {
                lastCheckInMinute = cp
                if let schedule = getCheckInSchedule(elapsedSeconds: elapsed) {
                    if !ScreenShareDetector.shared.isScreenSharing {
                        playGentleTap()
                    }
                    checkInData = schedule
                    showCheckIn = true
                    if schedule.level == .gentle {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                            self?.showCheckIn = false
                        }
                    }
                }
                break
            }
        }
    }

    // MARK: - Grace Period

    private func startGracePeriod() {
        graceActive = true
        graceTimer = Timer.scheduledTimer(withTimeInterval: 3 * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.graceActive = false
                self?.handleWorkComplete(stopReason: "timer")
            }
        }
    }

    func handleGraceDone() {
        graceTimer?.invalidate()
        graceTimer = nil
        graceActive = false
        handleWorkComplete(stopReason: "timer+grace")
    }

    // MARK: - Work Complete

    private func handleWorkComplete(stopReason: String, signals: [String] = []) {
        let entry = SessionEntry(
            mode: mode.id,
            focusSeconds: elapsed,
            stopReason: stopReason,
            signals: signals.isEmpty ? nil : signals
        )
        sessionLog.append(entry)
        DatabaseManager.shared.insertSession(entry)

        let newCycles = completedCycles + 1
        completedCycles = newCycles

        if mode.escalateHint != nil && newCycles >= 2 && stopReason == "timer" {
            showEscalateHint = true
            escalateTimer?.invalidate()
            escalateTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.showEscalateHint = false
                }
            }
        }

        if isFlowType {
            recommendedBreak = computeBreak(focusSeconds: elapsed)
            showBreakRec = true
        } else {
            transitionToBreak(cycles: newCycles)
        }
    }

    // MARK: - Break Transition

    func transitionToBreak(cycles: Int? = nil, customBreakMin: Int? = nil) {
        let c = cycles ?? (completedCycles + 1)
        let isLong = c % mode.cyclesBeforeLong == 0

        let breakMin: Int
        if let custom = customBreakMin {
            breakMin = custom
        } else if isFlowType {
            breakMin = recommendedBreak ?? computeBreak(focusSeconds: elapsed)
        } else {
            breakMin = isLong ? mode.longBreak : (mode.breakMin ?? 5)
        }

        phase = isLong ? .longBreak : .shortBreak
        timeLeft = breakMin * 60
        totalTime = breakMin * 60
        elapsed = 0
        isRunning = true
        graceActive = false
        showBreakRec = false
        lastCheckInMinute = -1

        startTick()
    }

    // MARK: - Start Work

    func startWorkPhase() {
        phase = .work
        elapsed = 0
        selectedSignals = []
        showCheckIn = false
        checkInData = nil
        lastCheckInMinute = -1
        workStartedAt = Date()

        if isFlowType {
            timeLeft = 0
            totalTime = 0
        } else if let w = mode.work {
            let secs = w * 60
            timeLeft = secs
            totalTime = secs
        }
        isRunning = true
        startTick()
    }

    // MARK: - User Actions

    func handleStart() {
        if phase == .idle {
            completedCycles = 0
            startWorkPhase()
        } else if breakEnded {
            startWorkPhase()
        } else {
            isRunning.toggle()
            if isRunning { startTick() } else { stopTick() }
        }
    }

    func handleReset() {
        stopTick()
        graceTimer?.invalidate()
        escalateTimer?.invalidate()
        phase = .idle
        timeLeft = 0
        totalTime = 0
        elapsed = 0
        isRunning = false
        completedCycles = 0
        graceActive = false
        showCheckIn = false
        checkInData = nil
        showSignalCheck = false
        selectedSignals = []
        showEscalateHint = false
        showBreakRec = false
        recommendedBreak = nil
        lastCheckInMinute = -1
        workStartedAt = nil
        showModeSwitchConfirm = false
        pendingModeIndex = nil
    }

    func handleFlowStop() {
        stopTick()
        isRunning = false
        showCheckIn = false
        if mode.type == .f1 {
            showSignalCheck = true
        } else {
            handleWorkComplete(stopReason: "manual", signals: [])
        }
    }

    func handleSignalSubmit() {
        showSignalCheck = false
        let sigs = Array(selectedSignals)
        selectedSignals = []
        let reason = sigs.count >= 2 ? "decay-signals" : "manual"
        handleWorkComplete(stopReason: reason, signals: sigs)
    }

    func handleSignalDismiss() {
        showSignalCheck = false
        selectedSignals = []
        handleWorkComplete(stopReason: "manual", signals: [])
    }

    func handleSkip() {
        stopTick()
        if phase == .work && !isFlowType {
            handleWorkComplete(stopReason: "skipped")
        } else if isBreak {
            isRunning = false
            showBreakRec = false
            startWorkPhase()
        }
    }

    func handleAcceptBreak(minutes: Int) {
        transitionToBreak(cycles: completedCycles, customBreakMin: minutes)
    }

    func handleSkipBreakRec() {
        showBreakRec = false
        startWorkPhase()
    }

    func toggleSignal(_ id: String) {
        if selectedSignals.contains(id) {
            selectedSignals.remove(id)
        } else {
            selectedSignals.insert(id)
        }
    }

    // MARK: - Mode Switch Guard

    /// Called when user taps a different mode while timer is active.
    /// During breaks: switch freely (next cycle uses new mode).
    /// During work, within 60s of starting: switch immediately.
    /// During work, after 60s: show confirmation dialog.
    func requestModeSwitch(to index: Int) {
        guard index != selectedModeIndex else { return }

        if phase == .idle {
            selectedModeIndex = index
            return
        }

        // During a break — switch mode freely for the next work cycle
        if phase.isBreak {
            switchModeDuringBreak(to: index)
            return
        }

        // Within the 60-second grace window — allow direct switch
        if let started = workStartedAt, Date().timeIntervalSince(started) < 60 {
            applyModeSwitch(to: index)
            return
        }

        // Locked — ask for confirmation
        pendingModeIndex = index
        showModeSwitchConfirm = true
    }

    /// Switch mode during a break — preserves the running break timer,
    /// only changes the mode so the next work phase uses the new settings.
    private func switchModeDuringBreak(to index: Int) {
        selectedModeIndex = index
        workStartedAt = nil
    }

    func confirmModeSwitch() {
        guard let index = pendingModeIndex else { return }
        showModeSwitchConfirm = false
        applyModeSwitch(to: index)
        pendingModeIndex = nil
    }

    func cancelModeSwitch() {
        showModeSwitchConfirm = false
        pendingModeIndex = nil
    }

    private func applyModeSwitch(to index: Int) {
        stopTick()
        graceTimer?.invalidate()
        escalateTimer?.invalidate()
        phase = .idle
        timeLeft = 0
        totalTime = 0
        elapsed = 0
        isRunning = false
        completedCycles = 0
        graceActive = false
        showCheckIn = false
        checkInData = nil
        showSignalCheck = false
        selectedSignals = []
        showEscalateHint = false
        showBreakRec = false
        recommendedBreak = nil
        lastCheckInMinute = -1
        workStartedAt = nil

        selectedModeIndex = index
    }

    func dismissCheckIn() {
        showCheckIn = false
    }

    func checkInTakeBreak() {
        showCheckIn = false
        handleFlowStop()
    }

    // MARK: - Audio & Notifications

    /// Smart notification: mutes audio during screen share, always sends system notification
    private func notifyCompletion(completedPhase: TimerPhase) {
        let silent = ScreenShareDetector.shared.isScreenSharing

        if !silent {
            playChime()
        }

        let title: String
        let body: String
        if completedPhase.isBreak {
            title = "Break Complete"
            body = "Time to focus again."
        } else {
            title = "\(mode.label) Complete"
            body = "Great work. Take a break."
        }
        NotificationManager.shared.send(title: title, body: body, silent: silent)

        // Visual alert (floating window or full-screen overlay, based on user preference)
        VisualAlertManager.shared.showAlert(title: title, body: body)
    }

    private func playChime() {
        // Respects system volume — NSSound follows system audio settings
        NSSound(named: .init("Blow"))?.play()
    }

    private func playGentleTap() {
        NSSound(named: .init("Tink"))?.play()
    }
}
