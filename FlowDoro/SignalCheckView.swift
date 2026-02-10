import SwiftUI

/// F1 signal check-in modal
struct SignalCheckView: View {
    @ObservedObject var engine: TimerEngine

    private var colors: ModeColorSet {
        modeColors(for: engine.mode, isBreak: false)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture {}

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.borderLight)
                        .frame(width: 36, height: 4)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    Text("Focus check-in")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.bottom, 4)

                    Text("\(engine.elapsed / 60)m in — experiencing any of these?")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .padding(.bottom, 16)

                    // Signal buttons
                    VStack(spacing: 8) {
                        ForEach(DECAY_SIGNALS) { sig in
                            Button {
                                engine.toggleSignal(sig.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(sig.icon)
                                        .font(.system(size: 18))
                                    Text(sig.label)
                                        .font(.system(size: 14))
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(engine.selectedSignals.contains(sig.id) ? Color.f1Accent.opacity(0.08) : Color.cardBg)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    engine.selectedSignals.contains(sig.id) ? Color.f1Accent : Color.borderLight,
                                                    lineWidth: 1.5
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // 2+ signals hint
                    if engine.selectedSignals.count >= 2 {
                        Text("2+ signals — time for a break (~\(computeBreak(focusSeconds: engine.elapsed))m recommended)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.f1Accent)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.f1Accent.opacity(0.06)))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        Button("Take break") {
                            engine.handleSignalDismiss()
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.953, green: 0.957, blue: 0.961)))
                        .buttonStyle(.plain)

                        Button(engine.selectedSignals.count >= 2 ? "Log & break" : "Log & break") {
                            engine.handleSignalSubmit()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(colors.accent))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
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
}
