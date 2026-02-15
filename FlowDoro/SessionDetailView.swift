import SwiftUI

/// Detail view for a single session — shows metadata and correlated app usage
struct SessionDetailView: View {
    let session: SessionEntry
    @Binding var isPresented: Bool
    @ObservedObject var activityTracker: AppActivityTracker

    @State private var appUsage: [AppUsageEntry] = []

    private var totalAppSeconds: Int {
        appUsage.reduce(0) { $0 + $1.totalSeconds }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Header
                    headerSection
                        .padding(.bottom, 12)
                        .overlay(
                            Rectangle().fill(Color(red: 0.953, green: 0.957, blue: 0.961)).frame(height: 1),
                            alignment: .bottom
                        )

                    // Content
                    ScrollView {
                        VStack(spacing: 16) {
                            sessionMetadataCard
                            appUsageSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 20)
                )
                .frame(maxWidth: 420, maxHeight: 500)
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            loadAppUsage()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.borderLight)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 12)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Detail")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(session.focusMinutes)m \(modeLabel) session")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .buttonStyle(.plain)
                .accessibilityLabel("Close session detail")
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Session Metadata

    private var sessionMetadataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode + duration
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(modeAccent)
                        .frame(width: 8, height: 8)
                    Text(modeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(session.focusMinutes)m")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
            }

            // Time range + stop reason
            HStack(spacing: 4) {
                Text(formattedTimeRange)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(session.stopReason)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.surfaceLight))
            }

            // Signals (F1 mode)
            if let signals = session.signals, !signals.isEmpty {
                Text("Signals: \(signals.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundColor(.f1Accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBg)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderLight, lineWidth: 1))
        )
    }

    // MARK: - App Usage

    private var appUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("APP USAGE DURING SESSION")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .tracking(0.5)
                Spacer()
                if totalAppSeconds > 0 {
                    Text(formatTotalTime(totalAppSeconds))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }

            if appUsage.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 24))
                        .foregroundColor(.textTertiary)
                    Text("No app activity recorded for this session")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(appUsage) { entry in
                    appRow(entry)
                }

                // Accuracy note
                Text("Approximate \u{00B7} based on app switching")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - App Row

    private func appRow(_ entry: AppUsageEntry) -> some View {
        let pct = totalAppSeconds > 0 ? Double(entry.totalSeconds) / Double(totalAppSeconds) : 0

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(appColor(entry.appName).opacity(0.12))
                    .frame(width: 32, height: 32)
                Text(String(entry.appName.prefix(1)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColor(entry.appName))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.appName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(entry.formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.textSecondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.borderLight)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(appColor(entry.appName))
                            .frame(width: geo.size.width * CGFloat(pct), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.cardBg))
    }

    // MARK: - Helpers

    private func loadAppUsage() {
        let start = session.startedAt
        let end = session.createdAt
        appUsage = activityTracker.usageDuring(from: start, to: end)
    }

    private var modeLabel: String {
        ALL_MODES.first(where: { $0.id == session.mode })?.label ?? session.mode
    }

    private var modeAccent: Color {
        switch session.mode {
        case "flow": return .flowAccent
        case "f1": return .f1Accent
        default: return .timerAccent
        }
    }

    private var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: session.startedAt)
        let end = formatter.string(from: session.createdAt)
        return "\(start) \u{2013} \(end)"
    }

    private func formatTotalTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m tracked" }
        if minutes > 0 { return "\(minutes)m tracked" }
        return "<1m tracked"
    }
}
