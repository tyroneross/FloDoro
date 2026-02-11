import Foundation
import AppKit
import SwiftUI

// MARK: - Alert Style Preference

enum VisualAlertStyle: Int {
    case none = 0
    case floating = 1
    case fullScreen = 2
}

// MARK: - Manager

/// Manages prominent visual alerts (floating window or full-screen overlay)
/// for timer completion. Follows singleton pattern consistent with NotificationManager.
@MainActor
final class VisualAlertManager {
    static let shared = VisualAlertManager()

    private var alertWindow: NSWindow?
    private var autoDismissTimer: Timer?

    private init() {}

    /// Show visual alert based on user preference. Called from TimerEngine.notifyCompletion.
    /// Suppressed during screen sharing unless `preview` is true.
    func showAlert(title: String, body: String, preview: Bool = false) {
        let rawValue = UserDefaults.standard.integer(forKey: "visualAlertStyle")
        let style = VisualAlertStyle(rawValue: rawValue) ?? .none
        guard style != .none else { return }

        // Don't show visual alerts during screen sharing / meetings (unless previewing)
        if !preview {
            guard !ScreenShareDetector.shared.isScreenSharing else { return }
        }

        dismissAlert()

        switch style {
        case .floating:
            showFloatingAlert(title: title, body: body)
        case .fullScreen:
            showFullScreenOverlay(title: title, body: body)
        case .none:
            break
        }

        // Dock bounce as fallback — bounces until user clicks
        NSApp.requestUserAttention(.criticalRequest)

        // Auto-dismiss after 30 seconds
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissAlert()
            }
        }
    }

    func dismissAlert() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        alertWindow?.orderOut(nil)
        alertWindow = nil
    }

    // MARK: - Floating Alert

    private func showFloatingAlert(title: String, body: String) {
        let contentView = FloatingAlertContent(title: title, message: body) { [weak self] in
            self?.dismissAlert()
        }

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 160)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = "FlowDoro"
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Position top-right of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 340
            let y = screenFrame.maxY - 180
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        alertWindow = panel
    }

    // MARK: - Full-Screen Overlay

    private func showFullScreenOverlay(title: String, body: String) {
        guard let screen = NSScreen.main else { return }

        let contentView = FullScreenAlertContent(title: title, message: body) { [weak self] in
            self?.dismissAlert()
        }

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = screen.frame

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false

        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        alertWindow = window
    }
}

// MARK: - Floating Alert Content

private struct FloatingAlertContent: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.49))
                }
                Spacer()
            }

            Button("Dismiss") {
                dismiss()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.49))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 0.9, green: 0.91, blue: 0.91), lineWidth: 1)
            )
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        )
    }
}

// MARK: - Full-Screen Overlay Content

private struct FullScreenAlertContent: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))

                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.49))

                Button {
                    dismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(red: 0.145, green: 0.388, blue: 0.922))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(32)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 40, y: 12)
            )
        }
    }
}
