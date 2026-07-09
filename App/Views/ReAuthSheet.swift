import SwiftUI
import GitHubKit
import CIStatusKit

/// The inline re-authentication UI shown beneath an account card while that
/// account is re-authenticating. Auth state and the polling task live on the
/// shared `AccountAuthCoordinator`.
struct ReAuthSheet: View {
    @Bindable var appState: AppState
    @Bindable var coordinator: AccountAuthCoordinator
    let account: Account

    var body: some View {
        switch coordinator.reAuthState {
        case .waitingForAuth(let code):
            deviceCodeCard(code)
        case .error(let message):
            errorCard(message)
        case .idle:
            EmptyView()
        }
    }

    private func deviceCodeCard(_ code: DeviceCode) -> some View {
        VStack(spacing: 10) {
            Text("Re-authenticating @\(account.username)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(code.userCode)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button("Copy Code & Open GitHub") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    NSWorkspace.shared.open(code.verificationURI)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancel") {
                    coordinator.cancelReAuth()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.06)))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 6) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Try Again") {
                    coordinator.startReAuth(for: account, appState: appState)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss") {
                    coordinator.cancelReAuth()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }
}
