import Foundation
import AppKit

/// Detects if the user is likely in a meeting or screen-sharing session.
/// Polls every 5 seconds — checks running apps only (no special permissions needed).
/// When active: audio notifications are muted, only visual indicators + silent banners used.
@MainActor
final class ScreenShareDetector: ObservableObject {
    static let shared = ScreenShareDetector()

    @Published private(set) var isScreenSharing: Bool = false

    private var pollTimer: Timer?

    /// Meeting/screen-sharing app bundle IDs
    private let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",                     // Zoom
        "com.microsoft.teams",              // Microsoft Teams (classic)
        "com.microsoft.teams2",             // Microsoft Teams (new)
        "com.cisco.webexmeetingsapp",       // Cisco Webex
        "com.cisco.webex.meetings",         // Webex (alt bundle)
        "com.apple.FaceTime",               // FaceTime
        "com.loom.desktop",                 // Loom
        "com.tinyspeck.slackmacgap",        // Slack (huddles)
        "com.discord.Discord",              // Discord (calls/streaming)
        "com.skype.skype",                  // Skype
        "com.brave.Browser.app.zoom",       // Brave Zoom integration
    ]

    private init() {
        startPolling()
    }

    private func startPolling() {
        checkNow()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNow()
            }
        }
    }

    private func checkNow() {
        isScreenSharing = detectMeetingApps()
    }

    /// Check if known meeting apps are running and visible (not hidden)
    private func detectMeetingApps() -> Bool {
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard let bundleID = app.bundleIdentifier else { continue }
            if meetingBundleIDs.contains(bundleID) && !app.isHidden && app.isActive == false {
                // App is running and not hidden — likely in a meeting
                // We check isActive == false to avoid false positive when
                // the user is just browsing Slack without a call.
                // Zoom/Teams/Webex run in foreground during calls regardless.
                return true
            }
            // Special case: Zoom and Teams show specific windows during calls
            if bundleID == "us.zoom.xos" || bundleID.hasPrefix("com.microsoft.teams") || bundleID == "com.cisco.webexmeetingsapp" {
                // If Zoom/Teams/Webex is running at all, assume a meeting context
                return true
            }
        }
        return false
    }

    deinit {
        pollTimer?.invalidate()
    }
}
