import Foundation

/// A version-tagged cache entry for a single repository's build status.
///
/// Stored as an array of these entries in UserDefaults. Entries are decoded
/// individually so a single corrupt or future-versioned entry doesn't nuke
/// the whole cache. The `version` field is optional for backward compatibility
/// with pre-v1 entries that predate the field — those are treated as v1.
public struct CachedRepoStatus: Codable, Sendable, Equatable {
    /// Current schema version for cached status entries. Bump when adding/removing
    /// fields or changing the encoding of `statusRaw` / `sourceRaw`.
    public static let currentVersion = 1

    /// Missing on pre-versioned entries; treat absence as `currentVersion` for
    /// backward compat with data written before this field existed.
    public var version: Int?
    public let repoID: Int
    public let statusRaw: String
    public let buildURL: URL?
    public let updatedAt: Date
    public let sourceRaw: String
    public let duration: TimeInterval?

    public init(
        version: Int? = currentVersion,
        repoID: Int,
        statusRaw: String,
        buildURL: URL?,
        updatedAt: Date,
        sourceRaw: String,
        duration: TimeInterval?
    ) {
        self.version = version
        self.repoID = repoID
        self.statusRaw = statusRaw
        self.buildURL = buildURL
        self.updatedAt = updatedAt
        self.sourceRaw = sourceRaw
        self.duration = duration
    }

    public init(repoID: Int, status: BuildStatus) {
        self.version = Self.currentVersion
        self.repoID = repoID
        self.statusRaw = Self.encodeStatus(status.status)
        self.buildURL = status.buildURL
        self.updatedAt = status.updatedAt
        self.sourceRaw = Self.encodeSource(status.source)
        self.duration = status.duration
    }

    /// Effective version — untagged (pre-v1) entries are treated as v1.
    public var effectiveVersion: Int { version ?? Self.currentVersion }

    public func toBuildStatus() -> BuildStatus? {
        guard let status = Self.decodeStatus(statusRaw),
              let source = Self.decodeSource(sourceRaw) else { return nil }
        return BuildStatus(status: status, buildURL: buildURL, updatedAt: updatedAt, source: source, duration: duration)
    }

    public static func encodeStatus(_ status: BuildStatus.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .success: "success"
        case .building: "building"
        case .pending: "pending"
        case .failure: "failure"
        }
    }

    public static func decodeStatus(_ raw: String) -> BuildStatus.Status? {
        switch raw {
        case "unknown": .unknown
        case "success": .success
        case "building": .building
        case "pending": .pending
        case "failure": .failure
        default: nil
        }
    }

    public static func encodeSource(_ source: BuildStatus.Source) -> String {
        switch source {
        case .actions: "actions"
        case .commitStatus: "commitStatus"
        case .combined: "combined"
        }
    }

    public static func decodeSource(_ raw: String) -> BuildStatus.Source? {
        switch raw {
        case "actions": .actions
        case "commitStatus": .commitStatus
        case "combined": .combined
        default: nil
        }
    }
}

/// Outcome of decoding a cached-statuses blob.
public struct CachedStatusDecodeResult: Sendable, Equatable {
    /// Entries that decoded cleanly and passed version checks.
    public let entries: [CachedRepoStatus]
    /// Number of entries that failed to decode or had an unsupported version.
    public let droppedCount: Int
    /// True if the top-level blob itself was corrupt (not a JSON array of objects).
    public let blobCorrupt: Bool

    public init(entries: [CachedRepoStatus], droppedCount: Int, blobCorrupt: Bool) {
        self.entries = entries
        self.droppedCount = droppedCount
        self.blobCorrupt = blobCorrupt
    }
}

public enum CachedStatusStore {
    /// Decode a `cachedStatuses` UserDefaults blob into individual entries.
    ///
    /// - Corrupt top-level blob → `blobCorrupt = true`, empty entries.
    /// - Individual entries that fail to decode → dropped, counted in `droppedCount`.
    /// - Entries whose `effectiveVersion` is not `CachedRepoStatus.currentVersion`
    ///   (including future versions) → dropped, counted in `droppedCount`.
    /// - Missing `version` field is treated as `currentVersion` (backward compat).
    public static func decode(_ data: Data?) -> CachedStatusDecodeResult {
        guard let data else {
            return CachedStatusDecodeResult(entries: [], droppedCount: 0, blobCorrupt: false)
        }
        guard let rawArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return CachedStatusDecodeResult(entries: [], droppedCount: 0, blobCorrupt: true)
        }
        let decoder = JSONDecoder()
        var entries: [CachedRepoStatus] = []
        var dropped = 0
        for raw in rawArray {
            guard let entryData = try? JSONSerialization.data(withJSONObject: raw),
                  let entry = try? decoder.decode(CachedRepoStatus.self, from: entryData) else {
                dropped += 1
                continue
            }
            guard entry.effectiveVersion == CachedRepoStatus.currentVersion else {
                dropped += 1
                continue
            }
            entries.append(entry)
        }
        return CachedStatusDecodeResult(entries: entries, droppedCount: dropped, blobCorrupt: false)
    }
}
