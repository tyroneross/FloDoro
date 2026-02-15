import SwiftUI

/// Session log modal with analytics
struct SessionLogView: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { engine.showLog = false }

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
                            Text("Session Log")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Button("Close") {
                                engine.showLog = false
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close session log")
                        }
                        .padding(.horizontal, 20)

                        // Insights
                        if engine.optimalWindow != nil || engine.avgFlowDuration != nil {
                            insightsCard
                        }

                        // Flow chart
                        if engine.flowSessions.count >= 2 {
                            flowChart
                        }
                    }
                    .padding(.bottom, 12)
                    .overlay(
                        Rectangle().fill(Color(red: 0.953, green: 0.957, blue: 0.961)).frame(height: 1),
                        alignment: .bottom
                    )

                    // Log entries
                    ScrollView {
                        if engine.sessionLog.isEmpty {
                            Text("Complete a focus cycle to start logging.")
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(engine.sessionLog.reversed()) { session in
                                    sessionRow(session)
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
                .frame(maxWidth: 420, maxHeight: 500)
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Insights

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let opt = engine.optimalWindow {
                Text("⭐ Optimal flow window: ~\(opt)m")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.purpleText)
            }
            if let avg = engine.avgFlowDuration {
                Text("Avg flow session: \(avg)m across \(engine.flowSessions.count) session\(engine.flowSessions.count != 1 ? "s" : "")")
                    .font(.system(size: 12))
                    .foregroundColor(.f1Accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.f1Accent.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.f1Accent.opacity(0.1), lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Flow Chart

    private var flowChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLOW SESSION LENGTHS")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .tracking(0.5)

            let sessions = Array(engine.flowSessions.suffix(12))
            let maxMin = max(sessions.map(\.focusMinutes).max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                    let height = max(4.0, Double(s.focusMinutes) / Double(maxMin) * 44.0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill((s.mode == "adaptive" || s.mode == "f1") ? Color.f1Accent.opacity(0.7) : Color.flowAccent.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(height))
                        .help("\(s.focusMinutes)m (\(s.mode))")
                }
            }
            .frame(height: 48)

            HStack {
                Text("oldest")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                Spacer()
                Text("recent")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: SessionEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(session.focusMinutes)m focus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Text("\(session.mode) · \(session.stopReason)")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
                if let signals = session.signals {
                    Text("Signals: \(signals.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(.f1Accent)
                }
            }
            Spacer()
            Text(session.timestamp)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.cardBg))
    }
}
