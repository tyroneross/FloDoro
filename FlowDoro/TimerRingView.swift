import SwiftUI

/// SVG-equivalent circular progress ring
struct TimerRingView: View {
    let progress: Double    // 0...1
    let accent: Color
    let displayTime: String
    let subtitle: String
    let isIdle: Bool

    private let ringSize: CGFloat = 220
    private let lineWidth: CGFloat = 3.5
    private var radius: CGFloat { (ringSize / 2) - lineWidth }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.borderLight, lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress ring
            if progress > 0 || !isIdle {
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: progress)
            }

            // Center text
            VStack(spacing: 6) {
                Text(displayTime)
                    .font(.system(size: isIdle ? 48 : 56, weight: .light, design: .monospaced))
                    .foregroundColor(isIdle ? .textTertiary : .textPrimary)
                    .animation(.easeInOut(duration: 0.3), value: isIdle)

                if !isIdle && !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer: \(displayTime)\(subtitle.isEmpty ? "" : ", \(subtitle)")")
        .accessibilityValue("\(Int(progress * 100)) percent complete")
    }
}
