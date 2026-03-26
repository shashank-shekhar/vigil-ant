import SwiftUI
import CIStatusKit
import GitHubKit

struct RepoRowView: View {
    let entry: RepoStatusEntry
    var isNotFound: Bool = false
    @State private var isSpinning = false

    var body: some View {
        HStack(spacing: 12) {
            if entry.status.status == .building {
                buildingIndicator
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.repo.fullName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isNotFound ? .secondary : .primary)

                if isNotFound {
                    Text("Repository not found — may have been deleted or transferred")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image("icon-arrow-right")
                .resizable()
                .frame(width: 12, height: 12)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if entry.status.status == .failure {
                Rectangle()
                    .fill(.red)
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.repo.fullName): \(accessibilityStatusLabel)")
        .accessibilityHint(entry.status.buildURL != nil ? String(localized: "Opens build in browser") : "")
        .onTapGesture {
            if let url = entry.status.buildURL {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var buildingIndicator: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.orange, lineWidth: 1.5)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
    }

    private var statusColor: Color {
        switch entry.status.status {
        case .success: .green
        case .failure: .red
        case .building: .orange
        case .pending: .yellow
        case .unknown: .gray
        }
    }

    private var accessibilityStatusLabel: String {
        switch entry.status.status {
        case .success: String(localized: "passing")
        case .failure: String(localized: "failing")
        case .building: String(localized: "building")
        case .pending: String(localized: "pending")
        case .unknown: String(localized: "no status")
        }
    }

    private var subtitle: String {
        let timeAgo = entry.status.updatedAt.formatted(.relative(presentation: .named))
        let verb: String = switch entry.status.status {
        case .success: String(localized: "Passed")
        case .failure: String(localized: "Failed")
        case .building: String(localized: "Building")
        case .pending: String(localized: "Pending")
        case .unknown: String(localized: "No status")
        }
        let durationPart = entry.status.duration.map { " · \(formatDuration($0))" } ?? ""
        let timePart: String = switch entry.status.status {
        case .unknown: ""
        case .building: ""
        default: " \(timeAgo)"
        }
        return "\(verb)\(timePart)\(durationPart) · \(entry.repo.defaultBranch)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
