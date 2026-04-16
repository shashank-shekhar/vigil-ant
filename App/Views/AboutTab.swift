import OSLog
import SwiftUI

struct AboutTab: View {
    @State private var showingLicenses = false
    @State private var logsCopyState: LogsCopyState = .idle

    private enum LogsCopyState {
        case idle, copying, copied
    }
    @State private var filterCopied = false

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

                Button(logsCopyLabel) {
                    copyCurrentSessionLogs()
                }
                .disabled(logsCopyState == .copying)

                Button(filterCopied ? "Filter copied!" : "Console") {
                    let subsystem = Bundle.main.bundleIdentifier ?? "net.shashankshekhar.vigilant"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("subsystem:\(subsystem)", forType: .string)
                    filterCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
                        )
                        filterCopied = false
                    }
                }
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

    private var logsCopyLabel: String {
        switch logsCopyState {
        case .idle: "Copy Logs"
        case .copying: "Copying\u{2026}"
        case .copied: "Copied!"
        }
    }

    private func copyCurrentSessionLogs() {
        logsCopyState = .copying
        Task.detached {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let position = store.position(timeIntervalSinceLatestBoot: 0)
                let entries = try store.getEntries(at: position)
                    .compactMap { $0 as? OSLogEntryLog }
                    .map { "[\($0.date.formatted(.iso8601))] [\($0.category)] \($0.composedMessage)" }

                let text = entries.joined(separator: "\n")
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text.isEmpty ? "No logs found for this session." : text, forType: .string)
                    logsCopyState = .copied
                }
            } catch {
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Failed to read logs: \(error.localizedDescription)", forType: .string)
                    logsCopyState = .copied
                }
            }
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                logsCopyState = .idle
            }
        }
    }
}
