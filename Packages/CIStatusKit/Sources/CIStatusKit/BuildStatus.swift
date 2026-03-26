import Foundation

public struct BuildStatus: Sendable {
    public enum Status: Sendable, Comparable {
        case unknown, success, building, pending, failure

        /// Higher raw value = worse status. Used for "worst of" aggregation.
        var severity: Int {
            switch self {
            case .unknown: 0
            case .success: 1
            case .building: 2
            case .pending: 3
            case .failure: 4
            }
        }
    }

    public enum Source: Sendable {
        case actions, commitStatus, combined
    }

    public let status: Status
    public let buildURL: URL?
    public let updatedAt: Date
    public let source: Source
    /// Duration of the workflow run. For completed runs this is the total time;
    /// for in-progress runs this is the elapsed time since the run started.
    public let duration: TimeInterval?

    public init(status: Status, buildURL: URL?, updatedAt: Date, source: Source, duration: TimeInterval? = nil) {
        self.status = status
        self.buildURL = buildURL
        self.updatedAt = updatedAt
        self.source = source
        self.duration = duration
    }

    /// Merge Actions workflow conclusion and Commit Status state into a single BuildStatus.
    /// - Failure if either reports failure (link points to the failing source)
    /// - Pending if either is pending and none are failing
    /// - Building if the Actions run is in-progress and nothing else is worse
    /// - Success if both report success
    /// - Unknown if no data from either source
    public static func merge(
        actionsConclusion: String?,
        actionsRunStatus: String? = nil,
        actionsRunStartedAt: Date? = nil,
        actionsUpdatedAt: Date? = nil,
        commitStatusState: String?,
        actionsURL: URL?,
        commitStatusURL: URL?,
        updatedAt: Date
    ) -> BuildStatus {
        // If the workflow run has no conclusion yet, check if it's actively running.
        let actionsStatus: Status? = if let conclusion = actionsConclusion {
            mapConclusion(conclusion)
        } else if let runStatus = actionsRunStatus {
            mapRunStatus(runStatus)
        } else {
            nil
        }
        let commitStatus = commitStatusState.map { mapState($0) }

        let statuses = [actionsStatus, commitStatus].compactMap { $0 }

        // Compute duration from run timing when available.
        let duration: TimeInterval? = if let startedAt = actionsRunStartedAt {
            (actionsUpdatedAt ?? updatedAt).timeIntervalSince(startedAt)
        } else {
            nil
        }

        guard !statuses.isEmpty else {
            return BuildStatus(status: .unknown, buildURL: nil, updatedAt: updatedAt, source: .combined, duration: nil)
        }

        let worst = statuses.max(by: { $0.severity < $1.severity })!

        // Determine which URL to surface and which source to label
        let (url, source): (URL?, Source) = {
            if actionsStatus == .failure && commitStatus != .failure {
                return (actionsURL, .actions)
            } else if commitStatus == .failure && actionsStatus != .failure {
                return (commitStatusURL, .commitStatus)
            } else if actionsStatus != nil && commitStatus != nil {
                return (actionsURL ?? commitStatusURL, .combined)
            } else if actionsStatus != nil {
                return (actionsURL, .actions)
            } else {
                return (commitStatusURL, .commitStatus)
            }
        }()

        return BuildStatus(status: worst, buildURL: url, updatedAt: updatedAt, source: source, duration: duration)
    }

    private static func mapConclusion(_ conclusion: String) -> Status {
        switch conclusion {
        case "success": .success
        case "failure", "timed_out", "cancelled": .failure
        case "action_required", "stale": .pending
        default: .unknown
        }
    }

    private static func mapRunStatus(_ status: String) -> Status {
        switch status {
        case "in_progress", "queued", "waiting", "requested", "pending": .building
        default: .unknown
        }
    }

    private static func mapState(_ state: String) -> Status {
        switch state {
        case "success": .success
        case "failure", "error": .failure
        case "pending": .pending
        default: .unknown
        }
    }
}
