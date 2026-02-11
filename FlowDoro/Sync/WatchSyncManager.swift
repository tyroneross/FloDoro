import Foundation
import os.log

// Conditional import — WatchConnectivity is only available on iOS and watchOS
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Watch Sync Manager
//
// Real-time sync between iPhone and Apple Watch via Watch Connectivity.
//
// Communication channels used:
// ┌────────────────────────────────────┬──────────────────────────────────┬─────────────────┐
// │ Method                             │ Use Case                         │ Delivery         │
// ├────────────────────────────────────┼──────────────────────────────────┼─────────────────┤
// │ sendMessage(_:)                    │ Timer state (start/pause/stop)   │ Instant (<1s)    │
// │ updateApplicationContext(_:)       │ Current mode, preferences        │ Next wake        │
// │ transferUserInfo(_:)               │ Completed session records         │ Background FIFO  │
// │ transferCurrentComplicationUserInfo│ Timer countdown for watch face   │ Priority         │
// └────────────────────────────────────┴──────────────────────────────────┴─────────────────┘
//
// Note: There is NO direct Mac ↔ Watch path. iPhone acts as bridge:
//   Mac ──[Network Framework]──► iPhone ──[Watch Connectivity]──► Watch

#if canImport(WatchConnectivity)

@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
    static let shared = WatchSyncManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro",
        category: "watch-sync"
    )

    /// Whether the counterpart app (Watch or iPhone) is currently reachable
    @Published private(set) var isReachable: Bool = false

    /// Whether Watch Connectivity is supported on this device
    @Published private(set) var isSupported: Bool = false

    /// Latest timer state received from counterpart
    @Published private(set) var remoteTimerState: TimerStateMessage?

    /// Callback for when a completed session is received from counterpart
    var onSessionReceived: ((FocusSession) -> Void)?

    /// Callback for when a timer state update is received
    var onTimerStateReceived: ((TimerStateMessage) -> Void)?

    private var session: WCSession?

    override private init() {
        super.init()
    }

    // MARK: - Activation

    /// Call once on app launch to activate Watch Connectivity
    func activate() {
        guard WCSession.isSupported() else {
            Self.logger.info("WCSession not supported on this device")
            isSupported = false
            return
        }

        isSupported = true
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        session = wcSession
        Self.logger.info("WCSession activation requested")
    }

    // MARK: - Send Timer State (Real-Time)

    /// Broadcast current timer state to counterpart.
    /// Uses sendMessage for instant delivery when reachable,
    /// falls back to applicationContext for eventual delivery.
    func sendTimerState(_ state: TimerStateMessage) {
        guard let session = session, session.activationState == .activated else { return }

        if session.isReachable {
            // Instant delivery — both apps are active
            session.sendMessage(state.asDictionary, replyHandler: nil) { error in
                Self.logger.warning("sendMessage failed: \(error.localizedDescription)")
                // Fall back to application context
                try? session.updateApplicationContext(state.asDictionary)
            }
        } else {
            // Eventual delivery — counterpart will get this on next wake
            do {
                try session.updateApplicationContext(state.asDictionary)
            } catch {
                Self.logger.warning("updateApplicationContext failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Send Completed Session (Guaranteed Delivery)

    /// Send a completed session to counterpart via transferUserInfo.
    /// Queued and delivered reliably in the background, even if the counterpart app isn't running.
    func sendCompletedSession(_ session: FocusSession) {
        guard let wcSession = self.session, wcSession.activationState == .activated else { return }

        let payload: [String: Any] = [
            "type": "sessionComplete",
            "id": session.id.uuidString,
            "mode": session.mode,
            "modeLabel": session.modeLabel,
            "focusSeconds": session.focusSeconds,
            "focusMinutes": session.focusMinutes,
            "stopReason": session.stopReason,
            "signals": session.signals ?? "",
            "sessionDate": session.sessionDate,
            "sessionTime": session.sessionTime,
            "createdAt": session.createdAt.timeIntervalSince1970,
            "deviceID": session.deviceID,
            "deviceType": session.deviceType
        ]

        wcSession.transferUserInfo(payload)
        Self.logger.info("Session queued for Watch transfer: \(session.mode) \(session.focusMinutes)m")
    }

    // MARK: - Update Complication (Priority Delivery)

    /// Update the watch face complication with current timer info.
    /// Budget-limited by Apple (~50 transfers per day).
    func updateComplication(timeRemaining: TimeInterval, mode: String, phase: String) {
        guard let session = self.session, session.activationState == .activated else { return }

        #if os(iOS)
        guard session.isComplicationEnabled else { return }
        guard session.remainingComplicationUserInfoTransfers > 0 else {
            Self.logger.info("No complication transfers remaining today")
            return
        }

        session.transferCurrentComplicationUserInfo([
            "timeRemaining": timeRemaining,
            "mode": mode,
            "phase": phase,
            "timestamp": Date().timeIntervalSince1970
        ])
        Self.logger.info("Complication updated: \(mode) \(Int(timeRemaining))s remaining")
        #endif
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            if let error = error {
                Self.logger.error("WCSession activation failed: \(error.localizedDescription)")
                return
            }
            self.isReachable = session.isReachable
            Self.logger.info("WCSession activated: \(activationState.rawValue)")
        }
    }

    // iOS only — required delegate methods
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Self.logger.info("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Self.logger.info("WCSession deactivated — reactivating")
        session.activate()
    }
    #endif

    // Reachability changed
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            Self.logger.info("WCSession reachability: \(session.isReachable)")
        }
    }

    // MARK: - Receive Messages

    /// Real-time message from counterpart (timer state updates)
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let timerState = TimerStateMessage(from: message) {
                self.remoteTimerState = timerState
                self.onTimerStateReceived?(timerState)
            }
        }
    }

    /// Application context update (mode/preferences sync)
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let timerState = TimerStateMessage(from: applicationContext) {
                self.remoteTimerState = timerState
                self.onTimerStateReceived?(timerState)
            }
        }
    }

    /// User info transfer (completed sessions — guaranteed background delivery)
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            guard let type = userInfo["type"] as? String, type == "sessionComplete" else { return }

            let focusSession = FocusSession()
            if let idStr = userInfo["id"] as? String {
                focusSession.id = UUID(uuidString: idStr) ?? UUID()
            }
            focusSession.mode = userInfo["mode"] as? String ?? "timer"
            focusSession.modeLabel = userInfo["modeLabel"] as? String ?? ""
            focusSession.focusSeconds = userInfo["focusSeconds"] as? Int ?? 0
            focusSession.focusMinutes = userInfo["focusMinutes"] as? Int ?? 0
            focusSession.stopReason = userInfo["stopReason"] as? String ?? "manual"
            let signalsStr = userInfo["signals"] as? String ?? ""
            focusSession.signals = signalsStr.isEmpty ? nil : signalsStr
            focusSession.sessionDate = userInfo["sessionDate"] as? String ?? ""
            focusSession.sessionTime = userInfo["sessionTime"] as? String ?? ""
            if let ts = userInfo["createdAt"] as? TimeInterval {
                focusSession.createdAt = Date(timeIntervalSince1970: ts)
            }
            focusSession.deviceID = userInfo["deviceID"] as? String ?? ""
            focusSession.deviceType = userInfo["deviceType"] as? String ?? ""

            self.onSessionReceived?(focusSession)
            Self.logger.info("Received session from counterpart: \(focusSession.mode) \(focusSession.focusMinutes)m")
        }
    }
}

#else

// MARK: - Stub for macOS (Watch Connectivity not available)

@MainActor
final class WatchSyncManager: ObservableObject {
    static let shared = WatchSyncManager()

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isSupported: Bool = false
    @Published private(set) var remoteTimerState: TimerStateMessage?

    var onSessionReceived: ((FocusSession) -> Void)?
    var onTimerStateReceived: ((TimerStateMessage) -> Void)?

    func activate() {
        // Watch Connectivity is not available on macOS
        isSupported = false
    }

    func sendTimerState(_ state: TimerStateMessage) {}
    func sendCompletedSession(_ session: FocusSession) {}
    func updateComplication(timeRemaining: TimeInterval, mode: String, phase: String) {}
}

#endif
