import SwiftUI
import GitHubKit
import CIStatusKit

/// The dashed "Add GitHub Account" entry button. Reused at the top of the
/// account list and as the idle state of `AddAccountSheet`.
struct AddAccountButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("+ Add GitHub Account")
                    .font(.system(size: 14, weight: .medium))
                Text("Sign in via GitHub Device Flow")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.quaternary)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The state-driven add-account UI: idle entry button, device-code card while
/// waiting for authorization, error card, and the repository-fetch progress
/// bar. All auth state and tasks live on the shared `AccountAuthCoordinator`.
struct AddAccountSheet: View {
    @Bindable var appState: AppState
    @Bindable var coordinator: AccountAuthCoordinator
    @State private var showCopied = false

    var body: some View {
        Group {
            switch coordinator.addState {
            case .idle:
                AddAccountButton { coordinator.startAddAccount(appState: appState) }

            case .waitingForAuth(let code):
                deviceCodeCard(code)

            case .error(let message):
                errorCard(message)
            }

            if let progress = coordinator.fetchProgress {
                fetchProgressView(current: progress.current, total: progress.total)
            }
        }
    }

    // MARK: - Waiting State

    private func deviceCodeCard(_ code: DeviceCode) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on GitHub:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text(code.userCode)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button(showCopied ? "Copied! Opening GitHub…" : "Copy Code & Open GitHub") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    showCopied = true
                    NSWorkspace.shared.open(code.verificationURI)
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showCopied = false
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    coordinator.cancelAddAccount()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for authorization...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }

    // MARK: - Error State

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Try Again") {
                    coordinator.startAddAccount(appState: appState)
                }
                .buttonStyle(.bordered)

                Button("Dismiss") {
                    coordinator.addState = .idle
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }

    // MARK: - Fetch Progress

    private func fetchProgressView(current: Int, total: Int) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(current), total: Double(total))
            Text("Fetching repositories... (\(current)/\(total))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }
}
