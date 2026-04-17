import SwiftUI

struct AboutTab: View {
    var sparkleUpdater: SparkleUpdater
    @State private var showingLicenses = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var commitHash: String {
        Bundle.main.infoDictionary?["GIT_COMMIT_HASH"] as? String ?? ""
    }

    private static let repoURL = "https://github.com/shashank-shekhar/vigil-ant"

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Vigil-ant"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .padding(.top, 8)

            Text(appName)
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .underline()
                    .onTapGesture {
                        NSWorkspace.shared.open(
                            URL(string: "\(Self.repoURL)/releases/tag/v\(appVersion)")!
                        )
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                Text("Build #\(buildNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !commitHash.isEmpty {
                    Text(String(commitHash.prefix(7)))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .underline()
                        .onTapGesture {
                            NSWorkspace.shared.open(
                                URL(string: "\(Self.repoURL)/commit/\(commitHash)")!
                            )
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
            }

            Text("Monitor GitHub CI/CD build status from your menu bar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 2) {
                Text("© 2026 Shashank Shekhar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: Self.repoURL)!)
                }

                Button("Licenses") {
                    showingLicenses = true
                }

                Button("Check for Updates…") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
            .font(.subheadline)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .sheet(isPresented: $showingLicenses) {
            LicensesView()
        }
    }
}
