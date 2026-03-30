import SwiftUI
import CIStatusKit
import GitHubKit

@MainActor
private func activateSettingsWindow() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
}

struct PopoverView: View {
    let appState: AppState
    var onRefresh: () -> Void = {}
    @State private var showQuitConfirmation = false

    private var aggregator: StatusAggregator { appState.aggregator }

    private var showWelcome: Bool {
        return appState.accounts.isEmpty && !appState.hasCompletedOnboarding
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label {
                    Text("CI Status")
                        .font(.system(size: 14, weight: .semibold))
                } icon: {
                    Image("icon-bug-ant-outline")
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
                SettingsLink {
                    Image("icon-settings")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    activateSettingsWindow()
                })

                Button {
                    showQuitConfirmation = true
                } label: {
                    Image("icon-power")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if showWelcome {
                WelcomeView()
            } else {
                // Auth error banner
                if !aggregator.authFailedAccountIDs.isEmpty {
                    authErrorBanner
                    Divider()
                }

                // Rate limit banner
                if !aggregator.rateLimitedAccountIDs.isEmpty {
                    rateLimitBanner
                    Divider()
                }

                // Repo list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(aggregator.sortedAccounts(), id: \.id) { account in
                            let entries = aggregator.sortedEntries(for: account.id)
                                .filter { $0.status.status != .unknown || $0.repo.hasWorkflows || aggregator.notFoundRepoIDs.contains($0.repo.id) }
                            if !entries.isEmpty {
                                AccountSectionView(
                                    account: account,
                                    entries: entries,
                                    notFoundRepoIDs: aggregator.notFoundRepoIDs
                                )
                            }
                        }
                    }
                }

                Divider()

                // Footer
                VStack(spacing: 4) {
                    HStack {
                        footerStatus
                        Spacer()
                        if let settingsTab = footerSettingsTab {
                            SettingsLink {
                                Text("Settings")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                appState.selectedSettingsTab = settingsTab
                                activateSettingsWindow()
                            })
                        } else {
                            Button("Refresh") { onRefresh() }
                                .font(.system(size: 12))
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                                .accessibilityHint(String(localized: "Refreshes CI status for all repositories"))
                        }
                    }
                    if !aggregator.rateLimitedAccountIDs.isEmpty,
                       let resetDate = aggregator.rateLimitResetDate,
                       resetDate > Date() {
                        HStack(spacing: 4) {
                            Image("icon-snail")
                                .resizable()
                                .frame(width: 10, height: 10)
                                .foregroundStyle(.secondary)
                            Text("Rate limit resets \(resetDate, format: .relative(presentation: .named))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 360, height: 480)
        .alert("Quit Vigil-ant?", isPresented: $showQuitConfirmation) {
            Button("Quit", role: .destructive) {
                NSApp.terminate(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will stop receiving CI status updates.")
        }
    }

    /// Returns which settings tab the footer should link to, or nil if Refresh should be shown.
    private var footerSettingsTab: AppState.SettingsTab? {
        if appState.accounts.isEmpty {
            return .accounts
        } else if !aggregator.authFailedAccountIDs.isEmpty {
            return .accounts
        } else if appState.repositories.filter({ $0.isMonitored }).isEmpty {
            return .repositories
        } else if appState.repositories.filter({ $0.isMonitored && $0.hasWorkflows }).isEmpty {
            return .repositories
        }
        return nil
    }

    @ViewBuilder
    private var footerStatus: some View {
        if appState.accounts.isEmpty {
            Text("Add a GitHub account in Settings")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if !appState.networkMonitor.isConnected {
            Text("Offline")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else if appState.repositories.filter({ $0.isMonitored }).isEmpty {
            Text("No repositories selected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if appState.repositories.filter({ $0.isMonitored && $0.hasWorkflows }).isEmpty {
            if let error = appState.workflowCheckError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("No CI workflows detected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if let lastUpdated = aggregator.lastUpdated {
            HStack(spacing: 4) {
                if appState.isStale {
                    Image("icon-triangle-alert")
                        .resizable()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(.orange)
                }
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(appState.isStale
                        ? "Last checked: \(lastUpdated, format: .relative(presentation: .named)) (stale)"
                        : "Last checked: \(lastUpdated, format: .relative(presentation: .named))")
                        .font(.system(size: 11))
                        .foregroundStyle(appState.isStale ? .orange : .secondary)
                }
            }
        }
    }

    private var authErrorBanner: some View {
        let names = aggregator.authFailedAccounts().map(\.name)
        let accountList = names.joined(separator: ", ")

        return HStack(spacing: 8) {
            Image("icon-triangle-alert")
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Authentication failed")
                    .font(.system(size: 12, weight: .medium))
                Text(names.isEmpty
                    ? String(localized: "Re-sign in from Settings.")
                    : String(localized: "\(accountList) — re-sign in from Settings."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SettingsLink {
                Text("Settings")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .simultaneousGesture(TapGesture().onEnded {
                activateSettingsWindow()
            })
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Authentication failed for \(accountList). Re-sign in from Settings."))
    }

    private var rateLimitBanner: some View {
        HStack(spacing: 8) {
            Image("icon-snail")
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(.secondary)

            if let resetDate = aggregator.rateLimitResetDate, resetDate > Date() {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text("Rate limit reached — resets \(resetDate, format: .relative(presentation: .named)).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("GitHub API rate limit reached — polling paused temporarily.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "GitHub API rate limit reached. Polling paused temporarily."))
    }
}
