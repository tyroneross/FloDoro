import SwiftUI

/// Shows app usage summary — which apps you've been using and for how long
struct ActivityView: View {
    @ObservedObject var tracker: AppActivityTracker
    @Binding var isPresented: Bool

    private var totalSeconds: Int {
        tracker.todaySummary.reduce(0) { $0 + $1.totalSeconds }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.borderLight)
                            .frame(width: 36, height: 4)
                            .padding(.top, 12)
                            .padding(.bottom, 12)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Activity")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Today · \(formatTotalTime(totalSeconds))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()

                            // Current app indicator
                            if !tracker.currentApp.isEmpty {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.breakAccent)
                                        .frame(width: 6, height: 6)
                                    Text(tracker.currentApp)
                                        .font(.system(size: 11))
                                        .foregroundColor(.textSecondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.breakAccent.opacity(0.08)))
                            }

                            Button("Close") {
                                isPresented = false
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 12)
                    .overlay(
                        Rectangle().fill(Color(red: 0.953, green: 0.957, blue: 0.961)).frame(height: 1),
                        alignment: .bottom
                    )

                    // App list
                    ScrollView {
                        if tracker.todaySummary.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 28))
                                    .foregroundColor(.textTertiary)
                                Text("App usage data will appear as you work")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(.vertical, 30)
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(tracker.todaySummary) { entry in
                                    appRow(entry)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 20)
                )
                .frame(maxWidth: 420, maxHeight: 460)
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - App Row

    private func appRow(_ entry: AppUsageEntry) -> some View {
        let pct = totalSeconds > 0 ? Double(entry.totalSeconds) / Double(totalSeconds) : 0

        return HStack(spacing: 12) {
            // App icon placeholder with first letter
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

                // Progress bar
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

    private func appColor(_ name: String) -> Color {
        // Assign consistent colors based on app name hash
        let colors: [Color] = [.timerAccent, .flowAccent, .f1Accent, .breakAccent, .levelFirm, .levelStrong]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }

    private func formatTotalTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m tracked"
        }
        if minutes > 0 {
            return "\(minutes)m tracked"
        }
        return "Just started"
    }
}
