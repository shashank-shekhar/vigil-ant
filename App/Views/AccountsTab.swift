import SwiftUI
import GitHubKit
import CIStatusKit

enum AddAccountState {
    case idle
    case waitingForAuth(DeviceCode)
    case error(String)
}

struct AccountsTab: View {
    @Bindable var appState: AppState
    @State private var addAccountState = AddAccountState.idle
    @State private var pollingTask: Task<Void, Never>?
    @State private var showCopied = false
    @State private var editingAccountID: UUID?
    @State private var accountToRemove: Account?
    @State private var fetchProgress: (current: Int, total: Int)?
    @State private var reAuthAccount: Account?
    @State private var reAuthState: AddAccountState = .idle
    @State private var reAuthPollingTask: Task<Void, Never>?

    private var sortedAccounts: [Account] {
        appState.accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if appState.accounts.count >= 3, case .idle = addAccountState {
                    addAccountButton
                }

                ForEach(sortedAccounts) { account in
                    VStack(spacing: 0) {
                        AccountCard(
                            account: account,
                            repoCount: appState.repositories.filter { $0.accountID == account.id && $0.isMonitored }.count,
                            isAuthFailed: appState.aggregator.authFailedAccountIDs.contains(account.id),
                            onChangeIcon: {
                                editingAccountID = account.id
                            },
                            onRemove: { accountToRemove = account },
                            onReAuthenticate: { startReAuthFlow(for: account) }
                        )
                        .popover(isPresented: Binding(
                            get: { editingAccountID == account.id },
                            set: { if !$0 { editingAccountID = nil } }
                        )) {
                            if let idx = appState.accounts.firstIndex(where: { $0.id == account.id }) {
                                AccountCustomizeView(account: $appState.accounts[idx])
                            }
                        }

                        if reAuthAccount?.id == account.id {
                            switch reAuthState {
                            case .waitingForAuth(let code):
                                reAuthDeviceCodeCard(code, account: account)
                            case .error(let message):
                                reAuthErrorCard(message)
                            case .idle:
                                EmptyView()
                            }
                        }
                    }
                }

                switch addAccountState {
                case .idle:
                    addAccountButton

                case .waitingForAuth(let code):
                    deviceCodeCard(code)

                case .error(let message):
                    errorCard(message)
                }

                if let progress = fetchProgress {
                    fetchProgressView(current: progress.current, total: progress.total)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .alert(
            "Remove @\(accountToRemove?.username ?? "account")?",
            isPresented: Binding(
                get: { accountToRemove != nil },
                set: { if !$0 { accountToRemove = nil } }
            )
        ) {
            if let account = accountToRemove {
                Button("Keep Repositories") {
                    appState.removeAccount(account, keepRepos: true)
                    accountToRemove = nil
                }
                Button("Discard Repositories", role: .destructive) {
                    appState.removeAccount(account, keepRepos: false)
                    accountToRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    accountToRemove = nil
                }
            }
        } message: {
            Text("Keeping repositories preserves your monitoring preferences when you re-add this account.")
        }
    }

    // MARK: - Idle State

    private var addAccountButton: some View {
        Button(action: { startDeviceFlow() }) {
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

    // MARK: - Waiting State

    private func deviceCodeCard(_ code: DeviceCode) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on GitHub:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(code.userCode)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    showCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showCopied = false
                    }
                }) {
                    Text(showCopied ? "Copied!" : "Copy")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button("Open GitHub") {
                    NSWorkspace.shared.open(code.verificationURI)
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    pollingTask?.cancel()
                    pollingTask = nil
                    addAccountState = .idle
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
                    startDeviceFlow()
                }
                .buttonStyle(.bordered)

                Button("Dismiss") {
                    addAccountState = .idle
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

    // MARK: - Re-Authentication Flow

    private func startReAuthFlow(for account: Account) {
        reAuthPollingTask?.cancel()
        reAuthAccount = account
        reAuthState = .idle

        let deviceFlow = DeviceFlowManager(clientID: OAuthConfig.clientID)

        reAuthPollingTask = Task {
            do {
                let code = try await deviceFlow.requestDeviceCode()
                reAuthState = .waitingForAuth(code)

                let tokenResponse = try await deviceFlow.pollForToken(deviceCode: code)

                appState.reAuthenticateAccount(
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

    private func reAuthDeviceCodeCard(_ code: DeviceCode, account: Account) -> some View {
        VStack(spacing: 10) {
            Text("Re-authenticating @\(account.username)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(code.userCode)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button("Open GitHub") {
                    NSWorkspace.shared.open(code.verificationURI)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Cancel") {
                    reAuthPollingTask?.cancel()
                    reAuthPollingTask = nil
                    reAuthAccount = nil
                    reAuthState = .idle
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

    private func reAuthErrorCard(_ message: String) -> some View {
        VStack(spacing: 6) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Try Again") {
                    if let account = reAuthAccount {
                        startReAuthFlow(for: account)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss") {
                    reAuthAccount = nil
                    reAuthState = .idle
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }

    // MARK: - Device Flow Logic

    private func startDeviceFlow() {
        let deviceFlow = DeviceFlowManager(clientID: OAuthConfig.clientID)

        pollingTask = Task {
            do {
                let code = try await deviceFlow.requestDeviceCode()
                addAccountState = .waitingForAuth(code)

                let tokenResponse = try await deviceFlow.pollForToken(deviceCode: code)
                let user = try await deviceFlow.fetchUser(token: tokenResponse.accessToken)

                if appState.accounts.contains(where: { $0.username == user.login }) {
                    addAccountState = .error("Account @\(user.login) is already added.")
                    return
                }

                let account = Account(name: user.name ?? user.login, username: user.login)
                addAccountState = .idle
                try appState.addAccount(account, token: tokenResponse.accessToken)

                // Save refresh token if the GitHub App uses expiring tokens
                if let refreshToken = tokenResponse.refreshToken {
                    try KeychainHelper.saveRefreshToken(refreshToken, for: account.id)
                }

                // Fetch repos and check which have workflows (batched)
                let client = GitHubAPIClient(token: tokenResponse.accessToken)
                let repoResponses = try await client.fetchRepositories()
                var repos: [Repository] = []
                let batchSize = 10
                fetchProgress = (current: 0, total: repoResponses.count)
                for batchStart in stride(from: 0, to: repoResponses.count, by: batchSize) {
                    let batch = repoResponses[batchStart..<min(batchStart + batchSize, repoResponses.count)]
                    let batchResults: [Repository] = await withTaskGroup(of: Repository.self) { group in
                        for resp in batch {
                            group.addTask {
                                let parts = resp.fullName.split(separator: "/")
                                let owner = String(parts[0])
                                let repoName = String(parts[1])
                                let has = (try? await client.fetchHasWorkflows(owner: owner, repo: repoName)) ?? false
                                return Repository(
                                    id: resp.id,
                                    fullName: resp.fullName,
                                    defaultBranch: resp.defaultBranch,
                                    isPrivate: resp.isPrivate,
                                    hasWorkflows: has,
                                    accountID: account.id,
                                    pushedAt: resp.pushedAt
                                )
                            }
                        }
                        var collected: [Repository] = []
                        for await repo in group {
                            collected.append(repo)
                        }
                        return collected
                    }
                    repos.append(contentsOf: batchResults)
                    fetchProgress = (current: repos.count, total: repoResponses.count)
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
                addAccountState = .idle
            } catch is CancellationError {
                fetchProgress = nil
                // User clicked Cancel
            } catch let error as DeviceFlowError {
                fetchProgress = nil
                addAccountState = .error(error.localizedDescription)
            } catch {
                fetchProgress = nil
                addAccountState = .error(String(localized: "Failed to add account: \(error.localizedDescription)"))
            }
        }
    }
}

struct AccountCard: View {
    let account: Account
    let repoCount: Int
    var isAuthFailed: Bool = false
    var onChangeIcon: () -> Void
    var onRemove: () -> Void
    var onReAuthenticate: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            IconImage(name: account.iconSymbol, size: 24)
                .foregroundStyle(isAuthFailed ? .orange : .primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.system(size: 14, weight: .semibold))
                Text("@\(account.username) · \(repoCount) repos monitored")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if isAuthFailed {
                    Label("Authentication failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)

                    Button("Re-authenticate", action: onReAuthenticate)
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .layoutPriority(1)

            Spacer()

            if !isAuthFailed {
                Button(action: onChangeIcon) {
                    Image("icon-settings")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onRemove) {
                Image("icon-trash")
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            if isAuthFailed {
                RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.06))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3))
            }
        }
    }
}
