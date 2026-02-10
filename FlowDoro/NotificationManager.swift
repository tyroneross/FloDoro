import Foundation
import AppKit
import UserNotifications

/// Handles macOS notification center integration.
/// Respects system Do Not Disturb / Focus modes automatically.
/// When `silent`: uses `.passive` interruption level (no sound, just notification center entry).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    /// Request notification permission and set self as delegate
    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[FlowDoro] Notification auth error: \(error.localizedDescription)")
            }
            if !granted {
                print("[FlowDoro] Notification permission denied — will rely on visual indicators only")
            }
        }
    }

    /// Send a notification banner
    func send(title: String, body: String, silent: Bool) {
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
                print("[FlowDoro] Notification send error: \(error.localizedDescription)")
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
