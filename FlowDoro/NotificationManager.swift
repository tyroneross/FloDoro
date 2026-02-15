import Foundation
import AppKit
import UserNotifications
import os.log

/// Handles macOS notification center integration.
/// Respects system Do Not Disturb / Focus modes automatically.
/// When `silent`: uses `.passive` interruption level (no sound, just notification center entry).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro", category: "notifications")

    private override init() {
        super.init()
    }

    /// Whether notifications are available (requires a proper app bundle)
    private(set) var isAvailable = false

    /// Request notification permission and set self as delegate
    func setup() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[FlowDoro] No bundle identifier — notifications disabled (run as .app bundle for full features)")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        isAvailable = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                Self.logger.error("Notification auth error: \(error.localizedDescription, privacy: .public)")
            }
            if !granted {
                Self.logger.info("Notification permission denied — will rely on visual indicators only")
            }
        }
    }

    /// Send a notification banner
    func send(title: String, body: String, silent: Bool) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if silent {
            // No sound — banner only, delivered passively
            content.sound = nil
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .passive
            }
        } else {
            // Default system notification sound — respects system volume
            content.sound = .default
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .active
            }
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Notification send error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap — bring app to front
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        completionHandler()
    }
}
