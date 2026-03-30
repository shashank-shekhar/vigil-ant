import SwiftUI
import GitHubKit

struct AccountCustomizeView: View {
    @Binding var account: Account
    private let symbols = [
        "icon-bug-ant-outline",
        "icon-cat", "icon-bird", "icon-rabbit", "icon-squirrel",
        "icon-ghost", "icon-skull", "icon-rocket", "icon-flame",
        "icon-star", "icon-heart", "icon-shield", "icon-crown",
        "icon-diamond", "icon-zap", "icon-leaf", "icon-moon", "icon-sun",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(account.name, text: Binding(
                    get: { account.displayName ?? "" },
                    set: { account.displayName = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
            }

            Divider()

            // Icon
            VStack(alignment: .leading, spacing: 10) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 12) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            account.iconSymbol = symbol
                        } label: {
                            IconImage(name: symbol, size: 20)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(account.iconSymbol == symbol ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Display
            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Toggle("Hide owner prefix from repo names", isOn: $account.hideOwnerPrefix)
                    .font(.system(size: 13))
            }

            Divider()

            // Notifications
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Toggle("Build failures", isOn: $account.notifyOnFailure)
                    .font(.system(size: 13))
                Toggle("Build fixed", isOn: $account.notifyOnFixed)
                    .font(.system(size: 13))
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
