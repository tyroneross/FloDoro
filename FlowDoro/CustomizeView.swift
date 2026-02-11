import SwiftUI

/// Modal for configuring Custom mode work/break durations
struct CustomizeView: View {
    @Binding var isPresented: Bool
    @AppStorage("customWorkMin") private var workMin: Int = 25
    @AppStorage("customBreakMin") private var breakMin: Int = 5

    private var ratio: String {
        let r = Double(workMin) / Double(max(breakMin, 1))
        if r == r.rounded() {
            return "\(Int(r)):1"
        }
        return String(format: "%.1f:1", r)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.borderLight)
                        .frame(width: 36, height: 4)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    Text("Customize Timer")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.bottom, 4)

                    Text("\(ratio) work/break ratio")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .padding(.bottom, 20)

                    // Work stepper
                    VStack(spacing: 16) {
                        stepperRow(
                            label: "Work",
                            value: workMin,
                            unit: "min",
                            range: 5...120,
                            step: 5,
                            onDecrement: { workMin = max(5, workMin - 5) },
                            onIncrement: { workMin = min(120, workMin + 5) }
                        )

                        Rectangle()
                            .fill(Color.borderLight)
                            .frame(height: 1)

                        stepperRow(
                            label: "Break",
                            value: breakMin,
                            unit: "min",
                            range: 1...30,
                            step: 1,
                            onDecrement: { breakMin = max(1, breakMin - 1) },
                            onIncrement: { breakMin = min(30, breakMin + 1) }
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // Done button
                    Button {
                        isPresented = false
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.timerAccent))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 20)
                )
                .frame(maxWidth: 360)
                .padding(.horizontal, 20)
            }
        }
    }

    private func stepperRow(
        label: String,
        value: Int,
        unit: String,
        range: ClosedRange<Int>,
        step: Int,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    onDecrement()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(value <= range.lowerBound ? .textTertiary : .textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.953, green: 0.957, blue: 0.961))
                        )
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text("\(value) \(unit)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 72)

                Button {
                    onIncrement()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(value >= range.upperBound ? .textTertiary : .textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.953, green: 0.957, blue: 0.961))
                        )
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
            }
        }
    }
}
