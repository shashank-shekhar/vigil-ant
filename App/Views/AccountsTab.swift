import SwiftUI
import GitHubKit
import CIStatusKit

struct AccountsTab: View {
    @Bindable var appState: AppState
    @State private var coordinator = AccountAuthCoordinator()
    @State private var editingAccountID: UUID?
    @State private var accountToRemove: Account?

    private var sortedAccounts: [Account] {
        appState.accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if appState.accounts.count >= 3, case .idle = coordinator.addState {
                    AddAccountButton { coordinator.startAddAccount(appState: appState) }
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
                            onReAuthenticate: { coordinator.startReAuth(for: account, appState: appState) }
                        )
                        .popover(isPresented: Binding(
                            get: { editingAccountID == account.id },
                            set: { if !$0 { editingAccountID = nil } }
                        )) {
                            if let idx = appState.accounts.firstIndex(where: { $0.id == account.id }) {
                                AccountCustomizeView(account: $appState.accounts[idx])
                            }
                        }

                        if coordinator.reAuthAccount?.id == account.id {
                            ReAuthSheet(appState: appState, coordinator: coordinator, account: account)
                        }
                    }
                }

                AddAccountSheet(appState: appState, coordinator: coordinator)
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
