import SwiftUI

struct AboutTab: View {
    @State private var showingLicenses = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Vigil-ant"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text(appName)
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Monitor GitHub CI/CD build status from your menu bar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("© 2026 Shashank Shekhar. MIT License.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: 12) {
                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shashank-shekhar/vigil-ant")!)
                }

                Button("Licenses") {
                    showingLicenses = true
                }
            }
            .font(.subheadline)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .sheet(isPresented: $showingLicenses) {
            LicensesView()
        }
    }
}
