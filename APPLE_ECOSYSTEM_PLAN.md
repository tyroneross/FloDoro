# FloDoro Apple Ecosystem Plan

## iOS + watchOS + macOS Multiplatform Architecture

---

## 1. Executive Summary

Transform FloDoro from a macOS-only menu bar app into a unified Apple ecosystem experience spanning **macOS**, **iOS/iPadOS**, and **watchOS**. All three apps share a single SwiftUI codebase, store data on-device using **SwiftData**, and sync automatically via **iCloud/CloudKit** — no external servers, no external databases.

---

## 2. Current State

| Aspect | Current |
|--------|---------|
| Platform | macOS 13+ only |
| UI | SwiftUI + AppKit (menu bar, NSWorkspace) |
| Storage | Raw SQLite (sessions.db, activity.db) |
| Auth | None |
| Sync | None |
| Dependencies | CSQLite (C module) |

### What Needs to Change

- **SQLite → SwiftData** (Apple's modern persistence with built-in CloudKit sync)
- **AppKit dependencies → platform-abstracted** (NSWorkspace, menu bar, etc.)
- **Single target → multiplatform Xcode project** with shared code + platform-specific targets
- **Add iCloud entitlement** for automatic cross-device sync

---

## 3. Project Structure

```
FloDoro/
├── FloDoro.xcodeproj
├── Shared/                          # All platforms
│   ├── App/
│   │   └── FloDoroApp.swift         # @main, SwiftUI App lifecycle
│   ├── Models/
│   │   ├── FocusSession.swift        # SwiftData @Model
│   │   ├── AppUsageRecord.swift      # SwiftData @Model
│   │   ├── WorkMode.swift            # Enum + config (unchanged logic)
│   │   ├── TimerPhase.swift          # Enum (unchanged)
│   │   └── CheckInLevel.swift        # Enum (unchanged)
│   ├── Engine/
│   │   ├── TimerEngine.swift         # Core timer logic (@Observable)
│   │   ├── SessionStore.swift        # SwiftData CRUD operations
│   │   ├── BreakCalculator.swift     # Break duration logic
│   │   └── CheckInScheduler.swift    # Progressive check-in logic
│   ├── Views/
│   │   ├── TimerView.swift           # Main timer display (adaptive layout)
│   │   ├── TimerRingView.swift       # Circular progress ring
│   │   ├── ModePickerView.swift      # Mode selection
│   │   ├── SessionLogView.swift      # Analytics/history
│   │   ├── CheckInView.swift         # Flow check-in overlay
│   │   ├── SignalCheckView.swift     # F1 decay signals
│   │   └── BreakRecView.swift        # Break recommendation
│   ├── Theme/
│   │   └── FloDoroTheme.swift        # Colors, fonts, spacing (per-platform)
│   ├── Sync/
│   │   ├── LocalSyncManager.swift    # Network Framework (Bonjour) for iPhone↔Mac
│   │   ├── WatchSyncManager.swift    # Watch Connectivity for iPhone↔Watch
│   │   └── SyncCoordinator.swift     # Orchestrates all 3 sync layers + relay
│   └── Utilities/
│       ├── Notifications.swift       # UNUserNotification abstraction
│       └── HapticsManager.swift      # Haptics (iOS/watchOS)
│
├── macOS/                            # macOS-only
│   ├── MenuBarManager.swift          # MenuBarExtra + popover
│   ├── AppActivityTracker.swift      # NSWorkspace frontmost app polling
│   ├── ScreenShareDetector.swift     # Meeting app detection
│   └── MacContentView.swift          # Window chrome, menu bar integration
│
├── iOS/                              # iOS/iPadOS-only
│   ├── iOSContentView.swift          # Tab-based or single-view layout
│   ├── ScreenTimeMonitor.swift       # DeviceActivity framework integration
│   ├── LiveActivityManager.swift     # Lock Screen Live Activity
│   └── WidgetExtension/              # Home Screen + StandBy widgets
│       ├── FloDoroWidget.swift
│       └── FloDoroLiveActivity.swift
│
├── watchOS/                          # watchOS-only
│   ├── WatchContentView.swift        # Compact timer UI
│   ├── WatchTimerView.swift          # Wrist-optimized ring + controls
│   ├── ComplicationProvider.swift    # WidgetKit complications
│   └── WatchHapticsManager.swift     # WKInterfaceDevice haptics
│
└── Tests/
    ├── TimerEngineTests.swift
    ├── BreakCalculatorTests.swift
    ├── SessionStoreTests.swift
    └── CheckInSchedulerTests.swift
```

### Key Principle: Maximum Code Sharing

Per [Apple's multiplatform app documentation](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target), use a **single multiplatform target** for shared code. Platform differences are handled via:

1. **`#if os()` guards** — sparingly, only for truly divergent APIs
2. **Protocol abstractions** — e.g., `AppUsageProvider` protocol with Mac/iOS implementations
3. **Parameterized modifiers** — platform-specific padding, sizing
4. **Separate view files** — when the UI is fundamentally different (watch vs. phone)

**Estimated code sharing: ~70-75% across all three platforms.**

---

## 4. Data Storage: SwiftData + iCloud

### 4.1 Why SwiftData (Not Raw SQLite)

| Feature | Raw SQLite (current) | SwiftData |
|---------|---------------------|-----------|
| iCloud sync | Manual implementation | Built-in, zero code |
| Multi-platform | Manual schema management | Automatic |
| Type safety | Manual mapping | Native Swift types via @Model |
| Migration | Manual SQL | Lightweight auto-migration |
| Apple ecosystem fit | External dependency | First-party framework |

SwiftData with CloudKit provides [automatic sync across all devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) signed into the same Apple ID. Data is stored locally first and synced when conditions allow — the app works fully offline.

### 4.2 Data Models (SwiftData)

```swift
import SwiftData

@Model
final class FocusSession {
    // CloudKit-compatible: no @Attribute(.unique), all optional or defaulted
    var id: UUID = UUID()
    var mode: String = "timer"           // "timer", "flow", "f1"
    var modeLabel: String = ""           // "Micro", "Pomodoro", etc.
    var focusSeconds: Int = 0
    var focusMinutes: Int = 0
    var stopReason: String = "manual"    // "timer", "manual", "hard-cap", "decay-signals", "timer+grace"
    var signals: String?                 // Comma-separated (F1 only)
    var sessionDate: String = ""         // "2026-02-11"
    var createdAt: Date = Date()
    var deviceID: String = ""            // Which device recorded this
    var deviceType: String = ""          // "mac", "iphone", "watch"
}

@Model
final class AppUsageRecord {
    var id: UUID = UUID()
    var appName: String = ""
    var bundleID: String = ""
    var durationSeconds: Int = 0
    var usageDate: String = ""
    var hour: Int = 0
    var createdAt: Date = Date()
    var source: String = ""              // "nsworkspace" (Mac), "screentime" (iOS)
    var deviceID: String = ""
}

@Model
final class UserPreferences {
    var id: UUID = UUID()
    var preferredMode: String = "pomodoro"
    var lastUpdated: Date = Date()
    var deviceID: String = ""
    // Syncs preferences across devices
}
```

### 4.3 CloudKit Compatibility Rules

Per [Apple's SwiftData + CloudKit documentation](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) and [community guidance](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/):

- **No `@Attribute(.unique)`** — CloudKit doesn't support uniqueness constraints
- **All properties must be optional or have defaults** — non-optional without defaults will silently fail sync
- **All relationships must be optional**
- **No `.deny` delete rules**
- **Schema changes must support lightweight migration** — once CloudKit is enabled, you cannot make breaking schema changes

### 4.4 ModelContainer Setup

```swift
@main
struct FloDoroApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            FocusSession.self,
            AppUsageRecord.self,
            UserPreferences.self
        ])
        let config = ModelConfiguration(
            "FloDoro",
            schema: schema,
            cloudKitDatabase: .automatic  // Enables iCloud sync
        )
        container = try! ModelContainer(for: schema, configurations: [config])
    }

    var body: some Scene {
        // Platform-specific scenes
    }
}
```

### 4.5 Sync Behavior

- **Local-first**: All reads/writes hit the local store instantly
- **Background sync**: Apple handles sync scheduling based on network, battery, user settings
- **Not real-time**: Behaves like Apple Notes/Photos — eventual consistency, usually seconds to minutes
- **Conflict resolution**: Last-writer-wins (Apple's default for private CloudKit)
- **Offline capable**: Full functionality without network — syncs when reconnected
- **Private database only**: Data is only accessible to the signed-in Apple ID

### 4.6 Known Limitation: Data on iCloud Toggle-Off

If the user disables iCloud sync for the app in Settings, **local data may be deleted**. Mitigation strategies:

1. Show a warning dialog before the user disables sync
2. Maintain a local-only backup store for critical session data
3. Document this behavior clearly for users

---

## 5. User Identity & Authentication

### 5.1 Recommendation: No Login Required

FloDoro is a **personal productivity tool** with private, per-user data. The recommended approach:

| Approach | Verdict |
|----------|---------|
| **No login at all** | **Recommended for v1** |
| Sign in with Apple | Optional future addition |
| Email/password | Not recommended — requires backend |
| OAuth (Google, etc.) | Not recommended — requires backend |

**Rationale**: iCloud sync is tied to the user's Apple ID at the OS level. SwiftData + CloudKit automatically syncs to the correct account. No explicit login needed.

### 5.2 Unique Device/User Identification

```swift
import Foundation

struct DeviceIdentifier {
    /// Stable per-device ID using identifierForVendor (iOS/watchOS)
    /// or a UUID stored in Keychain (macOS)
    static var current: String {
        #if os(iOS) || os(watchOS)
        return UIDevice.current.identifierForVendor?.uuidString
            ?? KeychainHelper.getOrCreateDeviceID()
        #elseif os(macOS)
        return KeychainHelper.getOrCreateDeviceID()
        #endif
    }

    /// Device type for analytics
    static var deviceType: String {
        #if os(watchOS)
        return "watch"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #elseif os(macOS)
        return "mac"
        #endif
    }
}
```

**Tracking without login**:
- Each `FocusSession` is stamped with `deviceID` and `deviceType`
- iCloud sync groups all sessions under the same Apple ID automatically
- Analytics can distinguish "sessions from my Watch vs. my Mac"
- No PII collected, no server, no account management burden

### 5.3 When to Add Sign in with Apple (Future)

Add [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) only if:
- You add social/sharing features (leaderboards, team focus sessions)
- You need a server-side component (web dashboard, API)
- You want to support non-Apple platforms

If added, the `sub` claim from Apple's identity token serves as the stable user ID, stored in Keychain. Still no external database needed for the core app.

---

## 6. Platform-Specific Features

### 6.1 macOS (Existing → Enhanced)

| Feature | Approach |
|---------|----------|
| Menu bar timer | Keep existing `MenuBarExtra` |
| App activity tracking | Keep `NSWorkspace` polling — macOS exclusive |
| Screen share detection | Keep existing detection |
| Window management | Keep existing 400×620 window |
| **New**: Widgets | Add WidgetKit widgets for Notification Center |

The macOS app retains all current functionality. Primary changes are the storage migration (SQLite → SwiftData) and extracting shared logic into the `Shared/` module.

### 6.2 iOS/iPadOS (New)

| Feature | Implementation |
|---------|---------------|
| **Timer + controls** | Shared `TimerView` with iOS-adapted layout |
| **App usage tracking** | DeviceActivity framework (Screen Time API) |
| **Lock Screen widget** | WidgetKit with timer countdown |
| **Live Activity** | Lock Screen + Dynamic Island during focus sessions |
| **StandBy mode** | Widget-based timer display |
| **Haptics** | UIImpactFeedbackGenerator for check-ins/transitions |
| **Focus mode integration** | Suggest system Focus mode during work sessions |
| **Background timer** | Timer continues via background task + local notification |

#### iOS App Usage Tracking

The Mac version uses `NSWorkspace` to track frontmost apps. iOS uses [Apple's Screen Time API](https://developer.apple.com/documentation/screentimeapidocumentation):

```swift
// Requires Family Controls entitlement
import DeviceActivity
import FamilyControls

class ScreenTimeMonitor: DeviceActivityMonitor {
    // Reports app usage during focus sessions
    // Data stays on-device (Apple's privacy requirement)
    // Can shield distracting apps during focus (optional future feature)
}
```

**Limitations to be aware of**:
- DeviceActivityMonitor extension has a ~5-6 MB memory limit
- Requires [Family Controls entitlement](https://developer.apple.com/documentation/xcode/configuring-family-controls) (special Apple approval)
- Usage data format differs from NSWorkspace — normalize into shared `AppUsageRecord`

#### iOS Live Activity (Lock Screen Timer)

```swift
import ActivityKit

struct FloDoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FloDoroAttributes.self) { context in
            // Lock Screen view
            TimerLiveActivityView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island (iPhone 14 Pro+)
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    TimerRingView(progress: context.state.progress)
                }
            } compactLeading: {
                Image(systemName: context.state.phase.iconName)
            } compactTrailing: {
                Text(timerInterval: context.state.timerRange)
            } minimal: {
                Image(systemName: "brain.head.profile")
            }
        }
        .supplementalActivityFamilies([.small]) // watchOS Smart Stack support
    }
}
```

This Live Activity [automatically appears in the Apple Watch Smart Stack](https://developer.apple.com/videos/play/wwdc2024/10068/) — giving the watch a timer display for free even before building dedicated watch features.

### 6.3 watchOS (New)

| Feature | Implementation |
|---------|---------------|
| **Timer display** | Compact `TimerRingView` optimized for wrist |
| **Start/pause/stop** | Digital Crown + tap controls |
| **Mode selection** | Simplified picker (3 modes on watch) |
| **Check-ins** | Haptic tap + simple dismiss |
| **Complications** | WidgetKit — current timer/phase on watch face |
| **Smart Stack widget** | Live timer + session count |
| **Independent operation** | Full timer functionality without iPhone |
| **Haptics** | `WKInterfaceDevice.current().play(.notification)` |

#### Watch-Specific Design Decisions

**Simplified mode set for watch**: Offer 3 modes on watch instead of 5:
- **Pomodoro** (25/5) — most common, works great on wrist
- **Flow** — adaptive, check-ins via haptic tap
- **F1** — with simplified signal selection (2-3 options instead of 4)

Micro and Extended can be triggered from the phone or Mac; they're less suited to the watch's interaction model.

**Timer continues on wrist-down**: Use [background tasks](https://developer.apple.com/documentation/WatchKit/using-background-tasks) + scheduled local notifications. The timer doesn't need to "run" — store the end time and compute remaining time on wake.

**Complications via WidgetKit**:
```swift
struct FloDoroComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FloDoro", provider: TimerTimelineProvider()) { entry in
            // Circular: timer ring
            // Rectangular: mode + time remaining
            // Corner: icon + time
        }
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}
```

### 6.4 Cross-Platform Feature Matrix

| Feature | macOS | iOS | watchOS |
|---------|-------|-----|---------|
| All 5 timer modes | Yes | Yes | 3 modes (Pomodoro/Flow/F1) |
| Timer ring UI | Yes | Yes | Yes (compact) |
| Progressive check-ins | Yes | Yes | Yes (haptic) |
| F1 decay signals | Yes | Yes | Yes (simplified) |
| Break recommendations | Yes | Yes | Yes (simplified) |
| Session history/analytics | Yes | Yes | Minimal (summary only) |
| App usage tracking | NSWorkspace | Screen Time API | No |
| Menu bar | Yes | N/A | N/A |
| Live Activity | N/A | Yes | Auto (via iOS) |
| Dynamic Island | N/A | Yes | N/A |
| Complications | N/A | N/A | Yes (WidgetKit) |
| Home Screen widgets | Notification Center | Yes | Smart Stack |
| Haptic feedback | No | Yes | Yes |
| Screen share detection | Yes | No | No |
| Independent operation | Yes | Yes | Yes |

---

## 7. Sync Architecture

### 7.1 How Sync Works

```
┌─────────┐     ┌──────────────────┐     ┌─────────┐
│  macOS   │     │   iCloud (CKZ)   │     │  iOS    │
│ SwiftData│◄───►│  Private Database │◄───►│SwiftData│
│  (local) │     │   (automatic)    │     │ (local) │
└─────────┘     └──────────────────┘     └─────────┘
                        ▲
                        │
                  ┌─────┘
                  │
              ┌───┴─────┐
              │ watchOS  │
              │ SwiftData│
              │  (local) │
              └──────────┘
```

- Each device writes sessions to its **local SwiftData store**
- SwiftData + CloudKit automatically syncs to iCloud's **private database**
- Other devices pick up changes on their next sync cycle
- **No server code, no API, no database to manage**

### 7.2 Conflict Scenarios & Resolution

| Scenario | Resolution |
|----------|-----------|
| Same session edited on two devices | Last-write-wins (CloudKit default) — unlikely for session logs since they're append-only |
| Preferences changed on two devices | Last-write-wins; `lastUpdated` timestamp shows which is newest |
| Timer running on two devices simultaneously | Each device writes its own session with its own `deviceID` — no conflict |
| Device offline for extended period | Syncs all accumulated sessions when back online |

**Sessions are append-only** (new record per focus session), so conflicts are nearly impossible for the core data.

### 7.3 What Syncs vs. What Doesn't

| Data | Syncs via iCloud | Rationale |
|------|-----------------|-----------|
| Focus sessions | Yes | Core data — history across all devices |
| User preferences | Yes | Same mode preferences everywhere |
| App usage records | Yes | Compare Mac vs. iPhone usage patterns |
| Timer state (running/paused) | **No** | Real-time state is device-local; each device runs independently |
| Notification permissions | **No** | Per-device OS setting |

### 7.4 Local Proximity Sync (Same WiFi / Nearby)

iCloud CloudKit sync has **~15 second latency at best** and push notifications [may not trigger while the app is in the foreground](https://developer.apple.com/forums/thread/761434). For near-instant sync when devices are nearby, FloDoro layers two additional real-time channels on top of CloudKit:

#### Architecture: Hybrid Sync

```
┌──────────────────────────────────────────────────────────┐
│                    SYNC LAYERS                           │
│                                                          │
│  Layer 1: iCloud/CloudKit (background, eventual)         │
│  ┌────────┐      ┌─────────┐      ┌─────────┐          │
│  │ macOS  │ ───► │ iCloud  │ ◄─── │  iOS    │          │
│  │        │      │ (≈15s)  │      │         │          │
│  └────────┘      └─────────┘      └─────────┘          │
│                       ▲                ▲                 │
│                       │                │                 │
│                  ┌────┘           ┌────┘                 │
│                  │ watchOS │      │                      │
│                  └─────────┘      │                      │
│                                   │                      │
│  Layer 2: Local Real-Time (same network, <1s)            │
│  ┌────────┐  Network Framework   ┌─────────┐           │
│  │ macOS  │ ◄──────────────────► │  iOS    │           │
│  │        │  NWBrowser/Listener  │  (hub)  │           │
│  └────────┘  Bonjour, <1s       └─────────┘           │
│                                       ▲                 │
│  Layer 3: Watch Connectivity (<1s)    │                 │
│                                  ┌────┘                 │
│                             ┌────┴────┐                 │
│                             │ watchOS │                 │
│                             │sendMsg()│                 │
│                             └─────────┘                 │
│                                                          │
│  iPhone acts as the BRIDGE between Mac and Watch         │
│  (no direct Mac ↔ Watch path exists)                    │
└──────────────────────────────────────────────────────────┘
```

#### Layer 1: iCloud/CloudKit (Baseline — Always Active)

- **What**: SwiftData auto-sync via CloudKit private database
- **Latency**: ~15 seconds best case; can be minutes in poor conditions
- **When**: Always active, handles cross-network and offline catch-up
- **Limitation**: [Foreground sync may stall](https://www.hackingwithswift.com/forums/swiftui/cloudkit-data-syncing-inconsistently/17703) — push notifications aren't always delivered while app is open
- **Mitigation**: Trigger `NSPersistentCloudKitContainer` manual import on `scenePhase` change; or use `CKSyncEngine` for more control

#### Layer 2: Network Framework — iPhone ↔ Mac (Same WiFi, <1s)

Apple [recommends Network framework over Multipeer Connectivity](https://developer.apple.com/forums/thread/776069) for new development. Multipeer Connectivity doesn't support watchOS and is nearing deprecation.

```swift
import Network

/// Mac side: advertise as listener
class LocalSyncListener {
    private var listener: NWListener?

    func start() throws {
        let params = NWParameters.tcp
        params.includePeerToPeer = true // Enables Bonjour peer-to-peer

        listener = try NWListener(using: params)
        listener?.service = NWListener.Service(
            name: "FloDoro-\(DeviceIdentifier.shortID)",
            type: "_flodoro._tcp"
        )
        listener?.newConnectionHandler = { connection in
            self.handleConnection(connection)
        }
        listener?.start(queue: .main)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        // Receive timer state updates, session completions, etc.
    }
}

/// iPhone side: browse for nearby FloDoro devices
class LocalSyncBrowser {
    private var browser: NWBrowser?

    func start() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: "_flodoro._tcp", domain: nil),
            using: params
        )
        browser?.browseResultsChangedHandler = { results, changes in
            // Discover Mac running FloDoro → connect
            for result in results {
                self.connectTo(result)
            }
        }
        browser?.start(queue: .main)
    }
}
```

**What syncs via this channel**:
- Timer state changes (start, pause, stop, phase transition) — so all devices reflect current state instantly
- Session completion events — appear in session log immediately
- Mode changes — if you switch mode on iPhone, Mac reflects it

**What does NOT sync here** (left to CloudKit):
- Historical session data (bulk)
- App usage records
- Preference changes

**Auto-discovery**: Bonjour service discovery means devices find each other automatically on the same WiFi — no pairing UI needed. The `_flodoro._tcp` service type is unique to the app.

#### Layer 3: Watch Connectivity — iPhone ↔ Apple Watch (<1s)

[Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity) is the **only** framework for real-time iPhone ↔ Watch communication. Per [WWDC 2021](https://developer.apple.com/videos/play/wwdc2021/10003/), it provides five transfer methods:

| Method | Use in FloDoro | Latency | Delivery |
|--------|---------------|---------|----------|
| **`sendMessage(_:)`** | Timer state changes (start/pause/stop) | Instant (<1s) | Only when both apps are reachable |
| **`updateApplicationContext(_:)`** | Current mode, preferences, latest session | Next wake | Guaranteed, last-value-wins |
| **`transferUserInfo(_:)`** | Completed session records | Background | Guaranteed, queued FIFO |
| **`transferCurrentComplicationUserInfo(_:)`** | Timer countdown for watch face complication | Immediate (budget-limited) | Priority delivery for complications |
| **`transferFile(_:)`** | Not used | Background | Guaranteed |

```swift
import WatchConnectivity

class WatchSyncManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSyncManager()
    private let session = WCSession.default

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send from iPhone to Watch (or vice versa)

    /// Real-time timer state (instant when both active)
    func sendTimerState(_ state: TimerStateMessage) {
        guard session.isReachable else {
            // Fall back to application context
            try? session.updateApplicationContext(state.asDictionary)
            return
        }
        session.sendMessage(state.asDictionary, replyHandler: nil)
    }

    /// Completed session (guaranteed background delivery)
    func sendCompletedSession(_ session: FocusSession) {
        self.session.transferUserInfo(session.asDictionary)
    }

    /// Update complication with current timer
    func updateComplication(timeRemaining: TimeInterval, mode: String) {
        guard session.remainingComplicationUserInfoTransfers > 0 else { return }
        session.transferCurrentComplicationUserInfo([
            "timeRemaining": timeRemaining,
            "mode": mode,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    // MARK: - Receive

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Handle incoming timer state from counterpart
        DispatchQueue.main.async {
            self.handleIncomingMessage(message)
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        // Handle mode/preference sync
        DispatchQueue.main.async {
            self.handleContextUpdate(applicationContext)
        }
    }
}
```

#### iPhone as the Bridge (Mac ↔ Watch)

There is **no direct Mac ↔ Apple Watch communication path**. The iPhone relays between them:

```
Mac ──[Network Framework]──► iPhone ──[Watch Connectivity]──► Watch
Mac ◄──[Network Framework]── iPhone ◄──[Watch Connectivity]── Watch
```

When the iPhone receives a timer state change from the Mac (via Network Framework), it immediately forwards it to the Watch (via `sendMessage`), and vice versa. This relay adds negligible latency (<100ms) since it's all local.

If the iPhone is not available, the Mac and Watch operate independently and sync later via CloudKit.

#### Discovery & Connection Lifecycle

```
App Launch
    │
    ├─ CloudKit sync activates automatically (SwiftData)
    │
    ├─ Network Framework: start browsing/listening for "_flodoro._tcp"
    │   └─ On discovery → auto-connect → exchange timer state
    │   └─ On disconnect → fall back to CloudKit only
    │
    └─ Watch Connectivity: activate WCSession
        └─ isReachable? → sendMessage for real-time
        └─ !isReachable → updateApplicationContext for eventual
```

No manual pairing, no settings, no "connect to device" UI. Everything auto-discovers and auto-connects when devices are nearby. Falls back gracefully when they're not.

#### What the User Experiences

| Scenario | Behavior |
|----------|----------|
| All devices on same WiFi | Timer state syncs in <1 second across all three devices |
| iPhone + Watch (no WiFi) | Bluetooth proximity handles Watch Connectivity — still <1s |
| Devices on different networks | CloudKit handles it — ~15s delay, fully automatic |
| One device offline | Works independently; syncs everything when back |
| iPhone not nearby (Mac + Watch only) | Each operates independently; no relay possible; CloudKit syncs sessions later |

### 7.5 Independent Operation

Each app works fully standalone:

- **Watch without iPhone**: Start a Pomodoro, get haptic check-ins, log the session. Syncs later.
- **iPhone without Mac**: Full timer + Live Activity + app usage tracking.
- **Mac without others**: Current full functionality preserved.
- **All offline**: Everything works. Sessions sync when connectivity returns.

---

## 8. Implementation Phases

### Phase 1: Foundation (Shared Core)

1. **Create Xcode multiplatform project** targeting macOS 14+, iOS 17+, watchOS 10+
2. **Migrate SQLite → SwiftData** models with CloudKit compatibility
3. **Extract shared engine**: TimerEngine, BreakCalculator, CheckInScheduler, SessionStore
4. **Add iCloud entitlement** + CloudKit container
5. **Write migration utility** to import existing SQLite sessions into SwiftData
6. **Add unit tests** for all shared engine logic

### Phase 2: macOS Parity

7. **Rebuild macOS app** on shared foundation
8. **Keep all macOS-specific features**: menu bar, NSWorkspace tracking, screen share detection
9. **Add macOS Notification Center widget** (WidgetKit)
10. **Verify iCloud sync** works for single-device (Mac)

### Phase 3: iOS App

11. **Build iOS UI**: adaptive layouts using shared views
12. **Implement Live Activity** + Dynamic Island for active timer
13. **Add iOS widgets**: Home Screen, StandBy, Lock Screen
14. **Integrate Screen Time API** for app usage tracking (or defer to Phase 5)
15. **Add haptic feedback** for check-ins and transitions
16. **Implement Network Framework local sync** (iPhone ↔ Mac, Bonjour `_flodoro._tcp`)
17. **Test cross-device sync**: Mac ↔ iPhone (CloudKit + local real-time)

### Phase 4: watchOS App

18. **Build watchOS UI**: compact timer, simplified mode picker
19. **Implement WidgetKit complications** for watch faces
20. **Add haptic check-ins** using WKInterfaceDevice
21. **Implement Watch Connectivity** (`sendMessage` + `applicationContext` + `transferUserInfo`)
22. **Build iPhone relay bridge** (Mac ↔ iPhone ↔ Watch real-time forwarding)
23. **Ensure independent operation** (timer works without iPhone)
24. **Test three-way sync**: Mac ↔ iPhone ↔ Watch (all three sync layers)

### Phase 5: Polish & Advanced Features

22. **Screen Time API integration** (iOS) — if deferred from Phase 3
23. **Focus mode suggestions** (iOS) — trigger system Focus during work sessions
24. **Siri Shortcuts** — "Start a Pomodoro" voice command
25. **App Intents** — Spotlight and Shortcuts integration
26. **Data export** — CSV/JSON export of session history
27. **Onboarding flow** — platform-appropriate first-run experience

---

## 9. Technical Requirements

### 9.1 Minimum Platform Versions

| Platform | Minimum | Rationale |
|----------|---------|-----------|
| macOS | 14 (Sonoma) | SwiftData requires macOS 14+ |
| iOS | 17 | SwiftData + Live Activities + StandBy |
| watchOS | 10 | SwiftData + modern WidgetKit complications |

### 9.2 Required Entitlements & Capabilities

| Capability | Platform | Purpose |
|------------|----------|---------|
| iCloud (CloudKit) | All | Data sync |
| Background Modes — Remote Notifications | All | CloudKit sync triggers |
| Background Modes — Background Processing | iOS | Timer continuation |
| WidgetKit | All | Widgets + complications |
| Family Controls | iOS (optional) | Screen Time API access |
| App Groups | iOS | Share data between app + widget/monitor extensions |

### 9.3 Apple Developer Program

Required for:
- CloudKit container provisioning
- App Store distribution
- Family Controls entitlement (if using Screen Time API)
- Push notification certificates (CloudKit sync)

---

## 10. Data Migration Strategy

### Migrating Existing SQLite Data

```swift
struct LegacyMigrator {
    /// Reads existing sessions.db and imports into SwiftData
    static func migrateIfNeeded(context: ModelContext) {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("FlowDoro")

        let sessionsDB = supportDir.appendingPathComponent("sessions.db")
        guard FileManager.default.fileExists(atPath: sessionsDB.path) else { return }
        guard !UserDefaults.standard.bool(forKey: "migrationCompleted") else { return }

        // Read from SQLite, write to SwiftData
        // ... (standard SQLite read → SwiftData insert loop)

        UserDefaults.standard.set(true, forKey: "migrationCompleted")
    }
}
```

Run once on first launch of the new macOS version. iPhone and Watch will receive the data via iCloud sync after migration.

---

## 11. Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SwiftData + CloudKit sync reliability | Data loss or silent sync failure | Test extensively on real devices; maintain local-only backup; follow CloudKit model rules strictly |
| iCloud toggle-off deletes local data | User loses session history | Warn user; consider dual-store (local-only + CloudKit) |
| Screen Time API entitlement rejection | Can't track iOS app usage | Make it optional; app works without it; can add later |
| watchOS background task limits | Timer doesn't fire check-in | Use scheduled notifications as fallback; store end-time, compute on wake |
| Schema migration breaks CloudKit | Existing data inaccessible | Plan schema carefully upfront; only additive changes after v1 |
| Memory limits on watchOS | Crashes on watch | Keep watch app minimal; offload analytics to phone |

---

## 12. Architecture Decision Records

### ADR-1: SwiftData over Core Data

**Decision**: Use SwiftData, not Core Data.
**Rationale**: SwiftData is Apple's recommended path forward. It provides the same CloudKit integration with less boilerplate. The app has no legacy Core Data investment. SwiftData's `@Model` macro aligns with the existing Swift struct-based models.

### ADR-2: No External Server

**Decision**: Zero server-side infrastructure. All storage is on-device + iCloud.
**Rationale**: FloDoro is a personal productivity tool. iCloud's private database handles sync. No social features require shared data. This eliminates hosting costs, server maintenance, authentication complexity, and GDPR/data-processing concerns.

### ADR-3: No Login Required (v1)

**Decision**: No Sign in with Apple or any authentication for v1.
**Rationale**: iCloud identity is implicit via the OS. Sessions are tagged with `deviceID` for analytics. Adding login adds friction for zero benefit when there's no server. Can be added in a future version if social features are introduced.

### ADR-4: Simplified Watch Experience

**Decision**: 3 modes on watch (Pomodoro, Flow, F1) instead of 5.
**Rationale**: Watch interaction should be quick and glanceable. Micro (12m) and Extended (50m) are niche modes that benefit from the richer Mac/phone UI. Users can still see synced sessions from any mode on any device.

### ADR-5: Live Activity as Watch Bridge

**Decision**: Implement iOS Live Activity with `.supplementalActivityFamilies([.small])` before building dedicated watch complications.
**Rationale**: Per [WWDC 2024](https://developer.apple.com/videos/play/wwdc2024/10068/), iOS Live Activities automatically appear in the watchOS Smart Stack. This gives Apple Watch users a timer display "for free" while the dedicated watch app is being built.

---

## 13. UI Optimization Per Platform

### 13.1 Design Language: Liquid Glass (iOS/macOS/watchOS 26)

Apple introduced [Liquid Glass](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/) at WWDC 2025 — a translucent material that reflects and refracts surroundings. It rolls out across iOS 26, macOS Tahoe 26, and watchOS 26. FloDoro should adopt it:

- **Recompile with Xcode 26** — framework views (tab bars, toolbars, sheets) update automatically
- **Apply `.glassEffect()` modifier** to custom surfaces (timer card, mode picker, analytics panels)
- **Use `.regular` glass** for primary surfaces (timer container), `.clear` glass for overlays (check-in sheets)
- **Tab bars shrink on scroll** automatically in iOS 26 — design the session log to work with this behavior
- **Partial-height sheets** get inset Liquid Glass backgrounds by default — break recommendation and signal check modals benefit from this for free

Reference: [Build a SwiftUI app with the new design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/323/)

---

### 13.2 iOS UI Optimization

#### Layout & Navigation

```
┌─────────────────────────────┐
│  [Timer]  [Log]  [Activity] │  ← Tab bar (Liquid Glass, shrinks on scroll)
│                             │
│    ┌───────────────────┐    │
│    │   ● POMODORO ●    │    │  ← Mode picker: horizontal scroll, pill-shaped
│    │                   │    │     selected mode uses accent glass effect
│    │    ╭─────────╮    │    │
│    │    │  18:42  │    │    │  ← Timer ring: hero element, centered
│    │    │   ◔     │    │    │     large, with .monospacedDigit() font
│    │    ╰─────────╯    │    │
│    │                   │    │
│    │  [ ▶ Start ]      │    │  ← Primary action: bottom third (thumb zone)
│    │  ○ ○ ● ○          │    │  ← Cycle dots
│    └───────────────────┘    │
│                             │
│  Tab Bar (glass)            │
└─────────────────────────────┘
```

#### Key iOS Optimizations

| Optimization | Implementation |
|-------------|----------------|
| **Thumb-zone controls** | Start/Pause/Stop buttons in bottom third of screen; mode picker at top (less frequent interaction) |
| **Large timer display** | Timer ring fills ~50% of screen width; time text uses SF Pro Rounded, `.largeTitle` weight |
| **`.monospacedDigit()`** | Prevents layout jitter as digits change during countdown |
| **Dynamic Type support** | All text scales with user's accessibility font size setting |
| **Dark mode** | Full support; timer ring glows subtly in dark mode using shadow with accent color |
| **Haptic feedback** | `UIImpactFeedbackGenerator(.medium)` on timer start/stop; `.light` on mode switch; `.heavy` on session complete |
| **Reduce Motion** | Respect `@Environment(\.accessibilityReduceMotion)` — skip ring animation, use fade transitions |
| **Lock Screen controls** | iOS 18+ Control Widget for start/pause from Lock Screen or Control Center |
| **StandBy mode** | Timer widget designed for landscape, large clock-style display |
| **Portrait orientation lock** | Timer view locked to portrait; analytics can rotate to landscape on iPad |

#### Live Activity & Dynamic Island

```
Dynamic Island (compact):
┌──────────────────────────────────┐
│ 🧠  │                    │ 18:42 │
└──────────────────────────────────┘

Dynamic Island (expanded):
┌──────────────────────────────────┐
│  Pomodoro          18:42         │
│  ████████████░░░░  Focus Phase   │
│                    [Pause]       │
└──────────────────────────────────┘

Lock Screen Live Activity:
┌──────────────────────────────────┐
│ 🧠 Pomodoro · Focus    18:42 ⏱️ │
│ ████████████████░░░░░░░░░░░░░░░ │
└──────────────────────────────────┘
```

- Use `Text(timerInterval:)` for **automatic countdown** without widget timeline updates
- Progress bar uses mode accent color (blue for timer, teal for flow, purple for F1)
- Compact trailing shows countdown; leading shows mode icon
- `.supplementalActivityFamilies([.small])` auto-renders on watchOS Smart Stack

#### Check-In Overlays (iOS)

- **Bottom sheet presentation** (`.presentationDetents([.medium])`) — doesn't cover timer
- Liquid Glass background on sheet
- Large tap targets (50pt minimum) for dismiss/extend buttons
- Haptic pulse accompanies each check-in level
- Auto-dismiss gentle alerts after 8 seconds (matches Mac behavior)

#### Session Log (iOS)

- **Swift Charts** for session history visualization (replaces custom bar chart)
- Pull-to-refresh gesture
- Swipe-to-delete individual sessions
- Filter chips: by mode, by device, by date range
- iPad: side-by-side layout (chart left, session list right) using `NavigationSplitView`

---

### 13.3 watchOS UI Optimization

#### Design Philosophy

Per Apple's [watchOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos): 60% of watch interactions last under 5 seconds. Every screen must answer the question: **"What's the one thing the user needs right now?"**

#### Main Timer View (Watch)

```
┌──────────────────┐
│                  │
│    ╭────────╮    │
│    │  18:42 │    │  ← Timer: fills most of the display
│    │   ◔    │    │     edge-to-edge, minimal padding
│    ╰────────╯    │
│                  │
│  POMODORO · ●●○○ │  ← Mode label + cycle dots (small)
│                  │
│   [ ▶ Start ]    │  ← Single full-width button
│                  │
└──────────────────┘
```

#### Key watchOS Optimizations

| Optimization | Implementation |
|-------------|----------------|
| **Full-screen color for state** | Black background during focus; accent color background when timer completes (like Apple's Timers app — [WWDC23 reference](https://developer.apple.com/videos/play/wwdc2023/10138/)) |
| **Edge-to-edge content** | Timer ring extends to display edges; minimize padding per HIG |
| **Single primary action** | One full-width button at bottom: Start → Pause → Resume → Done |
| **Digital Crown integration** | Scroll to switch modes (idle state); adjust break duration (break rec state) |
| **44pt+ tap targets** | All interactive elements minimum 44×44pt; prefer larger on curved display edges |
| **Haptic vocabulary** | `.start` for session begin; `.stop` for completion; `.click` for Digital Crown feedback; `.notification` for check-ins |
| **Minimal text** | Show time + mode only; no descriptions, no "best for" text |
| **Complications** | Circular: timer ring with time; Rectangular: mode + time + progress; Corner: icon + minutes; Inline: "18m left" |
| **Always-On Display** | Dim version: show time remaining + faint ring, reduce update frequency |
| **Reduce data density** | Session log on watch shows only today's count + total focus minutes; full history on phone/Mac |

#### Check-Ins (Watch)

```
┌──────────────────┐
│                  │
│   Still in the   │  ← Short text, large
│     zone? 🌬️    │
│                  │
│  [ Keep Going ]  │  ← Primary: full-width
│  [ Take Break ]  │  ← Secondary: full-width
│                  │
└──────────────────┘
```

- **Haptic tap** (`WKInterfaceDevice.current().play(.notification)`) alerts the user
- Two large buttons only — no multi-option complexity
- Auto-dismiss gentle check-ins after 5 seconds on watch (shorter than phone)
- Progressive color: background shifts from black → blue → teal → orange → red matching check-in level

#### F1 Signals (Watch — Simplified)

```
┌──────────────────┐
│  How's focus?     │
│                  │
│  [📖 Re-reading] │  ← 2 simplified options instead of 4
│  [🌊 Drifting ]  │     (covers the most common signals)
│                  │
│  [ Still Sharp ] │  ← "No decay" option
└──────────────────┘
```

- Reduce from 4 decay signals to 2 on watch (most actionable ones)
- Full-width buttons, large text
- "Still Sharp" = continue working (equivalent to selecting 0-1 signals)

#### Complications (WidgetKit)

```
Circular (watch face):        Rectangular (Smart Stack):
┌─────┐                      ┌──────────────────┐
│ ◔   │  ← Ring + time       │ 🧠 Pomodoro      │
│18:42│                      │ 18:42 remaining  │
└─────┘                      │ ●●○○  Cycle 2/4  │
                             └──────────────────┘

Corner:          Inline:
┌────┐
│ ⏱️ │           "FloDoro · 18m left"
│ 18m│
└────┘
```

- Use `Text(timerInterval:)` in WidgetKit for live countdown without frequent timeline updates
- Refresh complication timeline on session start, pause, stop, and phase transitions
- Show idle state: next suggested mode or "Start focus" prompt

---

### 13.4 macOS UI Enhancements

The current macOS UI is already well-designed. Enhancements for the multiplatform version:

| Enhancement | Details |
|-------------|---------|
| **Liquid Glass adoption** | Apply `.glassEffect()` to the timer card and mode picker in macOS Tahoe |
| **Notification Center widget** | WidgetKit widget showing current timer or "Start focus" prompt |
| **Menu bar → Liquid Glass** | Menu bar popover gets automatic Liquid Glass treatment in macOS 26 |
| **Keyboard shortcuts** | `⌘S` start/pause, `⌘R` reset, `⌘1-5` mode selection, `Space` start/pause |
| **Toolbar integration** | Use native `.toolbar` modifier for window controls instead of custom buttons |
| **Full-screen mode** | Optional full-screen distraction-free timer (just ring + time, nothing else) |
| **Multiple windows** | Allow opening session log in separate window via `WindowGroup` |

---

### 13.5 Shared UI Components (Cross-Platform)

These views are shared but adapt per platform:

```swift
struct TimerRingView: View {
    let progress: Double
    let phase: TimerPhase
    let mode: WorkMode

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: ringWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(mode.accentColor, style: StrokeStyle(
                    lineWidth: ringWidth,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)

            // Time display
            Text(timerInterval: timerRange)
                .font(timerFont)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: ringSize, height: ringSize)
    }

    // Platform-adaptive sizing
    private var ringSize: CGFloat {
        #if os(watchOS)
        return 120  // Compact for wrist
        #elseif os(iOS)
        return 220  // Hero element on phone
        #else
        return 180  // Fits macOS window
        #endif
    }

    private var ringWidth: CGFloat {
        #if os(watchOS)
        return 6    // Thicker for visibility at small size
        #else
        return 3.5  // Current Mac weight
        #endif
    }

    private var timerFont: Font {
        #if os(watchOS)
        return .system(size: 32, weight: .medium, design: .rounded)
        #elseif os(iOS)
        return .system(size: 48, weight: .light, design: .rounded)
        #else
        return .system(size: 36, weight: .light, design: .rounded)
        #endif
    }
}
```

### 13.6 Accessibility (All Platforms)

| Feature | Implementation |
|---------|---------------|
| **VoiceOver** | Timer announces remaining time on focus; mode and phase announced on change |
| **Dynamic Type** | All text scales; timer view uses fixed large size but labels scale |
| **Reduce Motion** | Disable ring animation; use opacity transitions instead |
| **Increase Contrast** | Higher contrast ring colors; solid backgrounds instead of glass effects |
| **Bold Text** | Respect system bold text preference |
| **Switch Control** | All interactive elements reachable via switch navigation |
| **Audio description** | Check-in alerts include spoken label for VoiceOver users |

---

## 14. Implementation Status

### Completed: Sync Layer Foundation (Phase 1 Core)

The following files have been implemented in `FlowDoro/Sync/`:

| File | Purpose | Status |
|------|---------|--------|
| `SyncModels.swift` | SwiftData `@Model` classes (`FocusSession`, `AppUsageRecord`, `UserPreferences`) + `TimerStateMessage` / `SessionCompleteMessage` for real-time sync | Done |
| `DeviceIdentifier.swift` | Stable per-device UUID via Keychain (macOS) / `identifierForVendor` (iOS/watchOS). Persists across reinstalls. | Done |
| `UserIdentityManager.swift` | Anonymous user tracking via `CKContainer.fetchUserRecordID()` — no login, no email, Apple ID is identity | Done |
| `CloudSyncManager.swift` | SwiftData `ModelContainer` with `cloudKitDatabase: .automatic`. CRUD operations for sessions, app usage, preferences. | Done |
| `MigrationManager.swift` | One-time SQLite → SwiftData migration for both `sessions.db` and `activity.db`. Idempotent, tagged as mac device. | Done |
| `WatchSyncManager.swift` | Watch Connectivity layer — `sendMessage()` for real-time, `transferUserInfo()` for session records, complication updates. macOS stub included. | Done |
| `LocalNetworkSync.swift` | Network Framework / Bonjour (`_flodoro._tcp`) — auto-discovery, TCP connections, length-framed JSON messaging, <1s latency. | Done |

### Configuration Changes

| File | Change |
|------|--------|
| `Package.swift` | Platform bumped from macOS 13 → macOS 14 (SwiftData requirement) |
| `FlowDoro.entitlements` | Added: iCloud/CloudKit container, network client/server, Keychain access groups |

### User Identity Approach: Zero Auth

Users are tracked anonymously via their Apple ID — no login screen, no phone verification, no backend:

1. **CloudKit private database** — tied to Apple ID at the OS level
2. **`CKContainer.fetchUserRecordID()`** — returns a stable anonymous user ID, same across all devices
3. **`DeviceIdentifier`** — per-device UUID stored in Keychain, stamped on every session for analytics
4. **SwiftData auto-sync** — write on Mac, appears on iPhone and Watch automatically

### Cross-Device Sync: 3 Layers

```
Layer 1: SwiftData + CloudKit (always active, ~15s)
  └─ All sessions, preferences, app usage sync via iCloud private DB

Layer 2: Network Framework / Bonjour (same WiFi, <1s)
  └─ Real-time timer state broadcast between Mac ↔ iPhone

Layer 3: Watch Connectivity (Bluetooth/WiFi, <1s)
  └─ iPhone ↔ Watch real-time timer + session delivery
  └─ iPhone acts as bridge: Mac ↔ iPhone ↔ Watch
```

### Remaining Work

- [ ] Integrate `CloudSyncManager` into `FlowDoroApp.swift` (replace `DatabaseManager` usage)
- [ ] Wire `TimerEngine` to broadcast state via `LocalNetworkSync` + `WatchSyncManager`
- [ ] Build iOS target with adaptive UI
- [ ] Build watchOS target with simplified UI
- [ ] Add WidgetKit widgets and complications
- [ ] Add Live Activity for iOS
- [ ] Implement Screen Time API integration (iOS, optional)
- [ ] End-to-end testing on real devices (Mac + iPhone + Watch)

---

## Sources

- [Apple: Configuring a multiplatform app](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target)
- [Apple: Food Truck multiplatform sample](https://developer.apple.com/documentation/swiftui/food-truck-building-a-swiftui-multiplatform-app)
- [Apple: Syncing model data across devices (SwiftData + CloudKit)](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Apple: Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)
- [Apple: Screen Time API frameworks](https://developer.apple.com/documentation/screentimeapidocumentation)
- [Apple: Bring your Live Activity to Apple Watch (WWDC 2024)](https://developer.apple.com/videos/play/wwdc2024/10068/)
- [Apple: Design Live Activities for Apple Watch (WWDC 2024)](https://developer.apple.com/videos/play/wwdc2024/10098/)
- [Apple: Background tasks in SwiftUI (WWDC 2022)](https://developer.apple.com/videos/play/wwdc2022/10142/)
- [Apple: Using background tasks (WatchKit)](https://developer.apple.com/documentation/WatchKit/using-background-tasks)
- [Apple: Migrating ClockKit to WidgetKit](https://developer.apple.com/documentation/widgetkit/converting-a-clockkit-app)
- [Apple: TN3157 — Updating watchOS project for SwiftUI/WidgetKit](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit)
- [Apple: Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [Hacking with Swift: Syncing SwiftData with CloudKit](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-sync-swiftdata-with-icloud)
- [Fat Bob Man: Key Considerations Before Using SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [Jesse Squires: Improving multiplatform SwiftUI code](https://www.jessesquires.com/blog/2023/03/23/improve-multiplatform-swiftui-code/)
- [Developer's Guide to Screen Time APIs](https://medium.com/@juliusbrussee/a-developers-guide-to-apple-s-screen-time-apis-familycontrols-managedsettings-deviceactivity-e660147367d7)
- [Apple: Introducing Liquid Glass design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [Apple: Build a SwiftUI app with the new design (WWDC 2025)](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Liquid Glass SwiftUI Reference (GitHub)](https://github.com/conorluddy/LiquidGlassReference)
- [Apple: Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple: Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Apple: Creating an intuitive UI in watchOS 10](https://developer.apple.com/documentation/watchos-apps/creating-an-intuitive-and-effective-ui-in-watchos-10)
- [Apple: Design and build apps for watchOS 10 (WWDC 2023)](https://developer.apple.com/videos/play/wwdc2023/10138/)
- [Apple: Watch Connectivity framework](https://developer.apple.com/documentation/watchconnectivity)
- [Apple: Transferring data with Watch Connectivity](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity)
- [Apple: There and back again — Data transfer on Apple Watch (WWDC 2021)](https://developer.apple.com/videos/play/wwdc2021/10003/)
- [Apple: Network framework](https://developer.apple.com/documentation/network)
- [Apple: Build device-to-device interactions with Network Framework (WWDC 2022)](https://developer.apple.com/videos/play/wwdc2022/110339/)
- [Apple: Supercharge device connectivity with Wi-Fi Aware (WWDC 2025)](https://developer.apple.com/videos/play/wwdc2025/228/)
- [Apple Developer Forums: Moving from Multipeer Connectivity to Network Framework](https://developer.apple.com/forums/thread/776069)
- [Apple Developer Forums: SwiftData and CloudKit sync latency](https://developer.apple.com/forums/thread/761434)
