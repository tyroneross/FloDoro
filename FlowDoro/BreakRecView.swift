import SwiftUI

/// Break recommendation modal for flow modes
struct BreakRecView: View {
    @ObservedObject var engine: TimerEngine
    let elapsed: Int
    let recommendedBreak: Int

    private var focusMinutes: Int { Int(round(Double(elapsed) / 60.0)) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture {} // absorb taps

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.borderLight)
                        .frame(width: 36, height: 4)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    // Focus summary
                    VStack(spacing: 4) {
                        Text("You focused for")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)

                        Text("\(focusMinutes) min")
                            .font(.system(size: 36, weight: .light, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .tracking(-0.5)

                        Text("Nice. Here's what your break should look like:")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.bottom, 20)

                    // Recommendation card
                    VStack(spacing: 4) {
                        Text("RECOMMENDED BREAK")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .tracking(0.5)

                        Text("\(recommendedBreak) min")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.breakAccent)

                        Text("~1 min per 5 min focus · Walk, stretch, detach")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.breakAccent.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.breakAccent.opacity(0.15), lineWidth: 1))
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // Quick adjust buttons
                    HStack(spacing: 6) {
                        let shorter = max(3, recommendedBreak - 3)
                        let longer = min(25, recommendedBreak + 5)

                        breakOption(minutes: shorter, label: "\(shorter)m shorter", isPrimary: false)
                        breakOption(minutes: recommendedBreak, label: "\(recommendedBreak)m", isPrimary: true)
                        breakOption(minutes: longer, label: "\(longer)m longer", isPrimary: false)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // Skip
                    Button("Skip break — keep working") {
                        engine.handleSkipBreakRec()
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 20)
                )
                .frame(maxWidth: 400)
                .padding(.horizontal, 20)
            }
        }
    }

    private func breakOption(minutes: Int, label: String, isPrimary: Bool) -> some View {
        Button {
            engine.handleAcceptBreak(minutes: minutes)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: isPrimary ? .semibold : .medium))
                .foregroundColor(isPrimary ? .white : .textPrimary.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isPrimary ? Color.breakAccent : Color(red: 0.953, green: 0.957, blue: 0.961))
                )
        }
        .buttonStyle(.plain)
    }
}
