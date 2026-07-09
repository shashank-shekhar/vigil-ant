import Foundation
import GitHubKit
import CIStatusKit

/// The phase of a device-flow auth attempt (add-account or re-auth).
enum AddAccountState {
    case idle
    case waitingForAuth(DeviceCode)
    case error(String)
}

/// Owns the add-account and re-authentication device-flow state and their
/// polling tasks. Keeping the `Task`s here (rather than in view `@State`, which
/// is fragile across view-identity changes) centralizes cancellation and lets
/// `AccountsTab` and its sub-sheets stay presentation-only.
@Observable
@MainActor
final class AccountAuthCoordinator {
    var addState: AddAccountState = .idle
    var fetchProgress: (current: Int, total: Int)?
    var reAuthAccount: Account?
    var reAuthState: AddAccountState = .idle

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var reAuthPollingTask: Task<Void, Never>?

    deinit {
        pollingTask?.cancel()
        reAuthPollingTask?.cancel()
    }

    // MARK: - Add Account

    func startAddAccount(appState: AppState) {
        let deviceFlow = DeviceFlowManager(clientID: OAuthConfig.clientID)

        pollingTask = Task {
            do {
                let code = try await deviceFlow.requestDeviceCode()
                addState = .waitingForAuth(code)

                let tokenResponse = try await deviceFlow.pollForToken(deviceCode: code)
                let user = try await deviceFlow.fetchUser(token: tokenResponse.accessToken)

                if appState.accounts.contains(where: { $0.username == user.login }) {
                    addState = .error("Account @\(user.login) is already added.")
                    return
                }

                let account = Account(name: user.name ?? user.login, username: user.login)
                addState = .idle
                try appState.addAccount(account, token: tokenResponse.accessToken)

                // Save refresh token if the GitHub App uses expiring tokens
                if let refreshToken = tokenResponse.refreshToken {
                    try KeychainHelper.saveRefreshToken(refreshToken, for: account.id)
                }

                // Fetch repos and resolve which have workflows via the shared
                // sliding-window fan-out, driving the progress bar from its callback.
                let client = GitHubAPIClient(token: tokenResponse.accessToken)
                let repoResponses = try await client.fetchRepositories()
                fetchProgress = (current: 0, total: repoResponses.count)
                var repos = await AppState.resolveRepositories(
                    from: repoResponses, accountID: account.id, client: client
                ) { completed, total in
                    self.fetchProgress = (current: completed, total: total)
                }
                fetchProgress = nil

                // Preserve monitoring preferences from previously disconnected accounts
                let previouslyMonitored = Set(appState.repositories.filter(\.isMonitored).map(\.id))
                for i in repos.indices {
                    if previouslyMonitored.contains(repos[i].id) {
                        repos[i].isMonitored = true
                    }
                }

                // Remove orphaned repos that match new ones, then add fresh data.
                // Only remove repos whose account no longer exists — don't touch
                // repos from other active accounts that share the same GitHub repo ID.
                let newIDs = Set(repos.map(\.id))
                let activeAccountIDs = Set(appState.accounts.map(\.id))
                appState.repositories.removeAll { newIDs.contains($0.id) && !activeAccountIDs.contains($0.accountID) }
                appState.repositories.append(contentsOf: repos)
                addState = .idle
            } catch is CancellationError {
                fetchProgress = nil
                // User clicked Cancel
            } catch let error as DeviceFlowError {
                fetchProgress = nil
                addState = .error(error.localizedDescription)
            } catch {
                fetchProgress = nil
                addState = .error(String(localized: "Failed to add account: \(error.localizedDescription)"))
            }
        }
    }

    func cancelAddAccount() {
        pollingTask?.cancel()
        pollingTask = nil
        addState = .idle
    }

    // MARK: - Re-Authentication

    func startReAuth(for account: Account, appState: AppState) {
        reAuthPollingTask?.cancel()
        reAuthAccount = account
        reAuthState = .idle

        let deviceFlow = DeviceFlowManager(clientID: OAuthConfig.clientID)

        reAuthPollingTask = Task {
            do {
                let code = try await deviceFlow.requestDeviceCode()
                reAuthState = .waitingForAuth(code)

                let tokenResponse = try await deviceFlow.pollForToken(deviceCode: code)

                try appState.reAuthenticateAccount(
                    account,
                    token: tokenResponse.accessToken,
                    refreshToken: tokenResponse.refreshToken
                )

                reAuthAccount = nil
                reAuthState = .idle
            } catch is CancellationError {
                // User clicked Cancel
            } catch let error as DeviceFlowError {
                reAuthState = .error(error.localizedDescription)
            } catch {
                reAuthState = .error(String(localized: "Re-authentication failed: \(error.localizedDescription)"))
            }
        }
    }

    func cancelReAuth() {
        reAuthPollingTask?.cancel()
        reAuthPollingTask = nil
        reAuthAccount = nil
        reAuthState = .idle
    }
}
