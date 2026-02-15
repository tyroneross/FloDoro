import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("visualAlertStyle") private var alertStyle: Int = 0
    @ObservedObject private var activityTracker = AppActivityTracker.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.borderLight)
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    // Header
                    HStack {
                        Text("Settings")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button("Close") { isPresented = false }
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Section header
                    Text("COMPLETION ALERT")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    // Alert style options
                    VStack(spacing: 0) {
                        alertOption(
                            label: "System notification only",
                            subtitle: nil,
                            value: 0
                        )
                        Divider().padding(.horizontal, 12)
                        alertOption(
                            label: "Floating window",
                            subtitle: "Small alert over all apps",
                            value: 1
                        )
                        Divider().padding(.horizontal, 12)
                        alertOption(
                            label: "Full-screen overlay",
                            subtitle: "Dims screen with message",
                            value: 2
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cardBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.borderLight, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Preview button
                    if alertStyle != 0 {
                        Button {
                            VisualAlertManager.shared.showAlert(
                                title: "Focus Complete",
                                body: "Great work. Take a break.",
                                preview: true
                            )
                        } label: {
                            Text("Preview alert")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.borderLight, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    } else {
                        Spacer().frame(height: 8)
                    }

                    // APP ACTIVITY section
                    Text("APP ACTIVITY")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Track app usage")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text("See which apps you use during focus sessions")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $activityTracker.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(.timerAccent)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cardBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.borderLight, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 20)
                )
                .frame(maxWidth: 400)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func alertOption(label: String, subtitle: String?, value: Int) -> some View {
        Button {
            alertStyle = value
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                }
                Spacer()
                if alertStyle == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.timerAccent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
