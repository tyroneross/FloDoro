import SwiftUI

/// Flow check-in nudge overlay (bottom sheet style)
struct CheckInView: View {
    @ObservedObject var engine: TimerEngine
    let data: CheckInData

    private var accent: Color { checkInAccentColor(for: data.level) }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(data.message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accent.opacity(0.9))

                        Text("\(engine.elapsed / 60)m elapsed · Break would be ~\(computeBreak(focusSeconds: engine.elapsed))m")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .padding(.bottom, 10)

                        HStack(spacing: 8) {
                            Button("Take a break") {
                                engine.checkInTakeBreak()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(accent))
                            .buttonStyle(.plain)
                            .accessibilityLabel("Take a break")

                            Button("Keep going") {
                                engine.dismissCheckIn()
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.953, green: 0.957, blue: 0.961)))
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss check-in and keep going")
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accent.opacity(0.15), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 360)
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}
