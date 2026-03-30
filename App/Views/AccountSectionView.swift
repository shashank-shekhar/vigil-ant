import SwiftUI
import GitHubKit
import CIStatusKit

struct AccountSectionView: View {
    let account: Account
    let entries: [RepoStatusEntry]
    var notFoundRepoIDs: Set<Int> = []

    var body: some View {
        Section {
            ForEach(entries, id: \.repo.id) { entry in
                RepoRowView(
                    entry: entry,
                    isNotFound: notFoundRepoIDs.contains(entry.repo.id),
                    hideOwnerPrefix: account.hideOwnerPrefix
                )
            }
        } header: {
            HStack(spacing: 6) {
                IconImage(name: account.iconSymbol, size: 11)
                Text(account.effectiveDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityLabel(String(localized: "\(account.effectiveDisplayName) account, \(entries.count) \(entries.count == 1 ? "repository" : "repositories")"))
        }
    }
}
