import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon and name
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .padding(.bottom, 12)

            Text("Vigil-ant")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 4)

            Text("Monitor your GitHub CI/CD builds from the menu bar")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Feature list
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "icon-shield", text: "Real-time build status monitoring")
                featureRow(icon: "icon-zap", text: "Instant failure notifications")
                featureRow(icon: "icon-star", text: "Multi-account support")
            }
            .padding(.top, 24)
            .padding(.bottom, 28)

            // Get Started button
            SettingsLink {
                Text("Get Started")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
            .padding(.horizontal, 48)

            Spacer()

            Text("Tip: Open settings anytime with the gear icon above")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(icon)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
        }
    }
}
