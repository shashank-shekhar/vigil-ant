import SwiftUI

struct AboutTab: View {
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

            VStack(spacing: 4) {
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Build \(buildNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !commitHash.isEmpty {
                    Text(String(commitHash.prefix(7)))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .underline()
                        .onTapGesture {
                            NSWorkspace.shared.open(
                                URL(string: "https://github.com/shashank-shekhar/vigil-ant/commit/\(commitHash)")!
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

                Button("Logs") {
                    let command = "log stream --predicate 'subsystem == \"net.shashankshekhar.vigilant\"' --level debug"
                    let source = "tell application \"Terminal\"\nactivate\ndo script \"\(command)\"\nend tell"
                    if let script = NSAppleScript(source: source) {
                        var error: NSDictionary?
                        script.executeAndReturnError(&error)
                    }
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
