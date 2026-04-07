import SwiftUI
import GitHubKit
import CIStatusKit

enum RepoSortOrder: String, CaseIterable {
    case name = "Name"
    case recentActivity = "Recent Activity"
}

struct RepositoriesTab: View {
    @Bindable var appState: AppState
    @State private var searchText = ""
    @State private var collapsedAccounts: Set<UUID> = []
    @AppStorage("repoSortOrder") private var sortOrder: String = RepoSortOrder.name.rawValue
    @AppStorage("repoEnabledFirst") private var enabledFirst = false

    private var selectedSort: RepoSortOrder {
        RepoSortOrder(rawValue: sortOrder) ?? .name
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Filter repositories...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Sort:", selection: $sortOrder) {
                        ForEach(RepoSortOrder.allCases, id: \.rawValue) { order in
                            Text(order.rawValue).tag(order.rawValue)
                        }
                    }
                    .fixedSize()

                    Toggle("Enabled first", isOn: $enabledFirst)
                        .fixedSize()
                }

                HStack(spacing: 0) {
                    let allSelected = !appState.repositories.isEmpty && appState.repositories.allSatisfy(\.isMonitored)
                    Button(allSelected ? "Deselect All" : "Select All") {
                        let newValue = !allSelected
                        for idx in appState.repositories.indices {
                            appState.repositories[idx].isMonitored = newValue
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Text(" | ")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)

                    Button("Select All with CI") {
                        for idx in appState.repositories.indices where appState.repositories[idx].hasWorkflows {
                            appState.repositories[idx].isMonitored = true
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Spacer()

                    Text("\(appState.repositories.filter(\.isMonitored).count)/\(appState.repositories.count) selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await appState.syncRepositories() }
                    } label: {
                        if appState.isSyncingRepos {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(appState.isSyncingRepos)
                    .help("Refresh repository list from GitHub")
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            List {
                ForEach(appState.accounts) { account in
                    let repos = filteredRepos(for: account.id)
                    Section {
                        if !collapsedAccounts.contains(account.id) {
                            ForEach(repos.indices, id: \.self) { index in
                                repoRow(repos[index])
                            }
                        }
                    } header: {
                        sectionHeader(account: account, repos: repos)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    if collapsedAccounts.contains(account.id) {
                                        collapsedAccounts.remove(account.id)
                                    } else {
                                        collapsedAccounts.insert(account.id)
                                    }
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func sectionHeader(account: Account, repos: [Repository]) -> some View {
        let isCollapsed = collapsedAccounts.contains(account.id)
        return HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            IconImage(name: account.iconSymbol)
            Text(account.name)
            Spacer()
            let monitored = repos.filter(\.isMonitored).count
            Text("\(monitored)/\(repos.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            Color.white.opacity(0.06)
                .padding(.horizontal, -20)
                .padding(.vertical, -6)
        )
    }

    private func filteredRepos(for accountID: UUID) -> [Repository] {
        var repos = appState.repositories
            .filter { $0.accountID == accountID }
            .filter { searchText.isEmpty || $0.fullName.localizedCaseInsensitiveContains(searchText) }

        repos.sort { a, b in
            if enabledFirst && a.isMonitored != b.isMonitored {
                return a.isMonitored
            }
            switch selectedSort {
            case .name:
                return a.fullName.localizedCaseInsensitiveCompare(b.fullName) == .orderedAscending
            case .recentActivity:
                let aDate = lastActivityDate(for: a)
                let bDate = lastActivityDate(for: b)
                return aDate > bDate
            }
        }

        return repos
    }

    /// Returns the last CI activity date from polled build/workflow data only.
    /// Does not fall back to pushedAt, which includes Dependabot and other bot pushes.
    private func lastActivityDate(for repo: Repository) -> Date {
        if let date = appState.aggregator.repoStatuses[repo.id]?.status.updatedAt,
           date != .distantPast {
            return date
        }
        return .distantPast
    }

    private func repoRow(_ repo: Repository) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(repo.fullName)
                    .font(.system(size: 13))
                HStack(spacing: 4) {
                    Text(repo.isPrivate ? String(localized: "Private") : String(localized: "Public"))
                    if !repo.hasWorkflows {
                        Text("· No CI")
                    }
                    let activityDate = lastActivityDate(for: repo)
                    if activityDate != .distantPast {
                        Text("· \(activityDate, format: .relative(presentation: .named))")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding(for: repo))
                .labelsHidden()
        }
    }

    private func binding(for repo: Repository) -> Binding<Bool> {
        Binding(
            get: { repo.isMonitored },
            set: { newValue in
                if let idx = appState.repositories.firstIndex(where: { $0.id == repo.id }) {
                    appState.repositories[idx].isMonitored = newValue
                }
            }
        )
    }
}
