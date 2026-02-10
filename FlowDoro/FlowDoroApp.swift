import SwiftUI

@main
struct FlowDoroApp: App {
    @StateObject private var engine = TimerEngine()

    init() {
        // Start notification system
        NotificationManager.shared.setup()
        // Start screen-share detection polling
        _ = ScreenShareDetector.shared
        // Start app activity tracking
        _ = AppActivityTracker.shared
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView(engine: engine)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 620)

        // Menu bar item — always visible, shows countdown
        MenuBarExtra {
            MenuBarContentView(engine: engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
