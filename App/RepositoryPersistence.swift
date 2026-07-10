import Foundation
import GitHubKit
import CIStatusKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RepositoryPersistence")

// MARK: - Cached Status Entry

/// Codable snapshot of a repo's build status, persisted to UserDefaults so the
/// popover can show last-known state immediately on launch.
struct CachedRepoStatus: Codable {
    /// Current schema version for cached status entries. Bump when adding/removing
    /// fields or changing the encoding of `statusRaw` / `sourceRaw`.
    static let currentVersion = 1

    /// Missing on pre-versioned entries; treat absence as `currentVersion` for
    /// backward compat with data written before this field existed.
    var version: Int?
    let repoID: Int
    let statusRaw: String
    let buildURL: URL?
    let updatedAt: Date
    let sourceRaw: String
    let duration: TimeInterval?

    init(repoID: Int, entry: RepoStatusEntry) {
        self.version = Self.currentVersion
        self.repoID = repoID
        self.statusRaw = Self.encodeStatus(entry.status.status)
        self.buildURL = entry.status.buildURL
        self.updatedAt = entry.status.updatedAt
        self.sourceRaw = Self.encodeSource(entry.status.source)
        self.duration = entry.status.duration
    }

    /// Effective version — untagged (pre-v1) entries are treated as v1.
    var effectiveVersion: Int { version ?? Self.currentVersion }

    func toBuildStatus() -> BuildStatus? {
        guard let status = Self.decodeStatus(statusRaw),
              let source = Self.decodeSource(sourceRaw) else { return nil }
        return BuildStatus(status: status, buildURL: buildURL, updatedAt: updatedAt, source: source, duration: duration)
    }

    private static func encodeStatus(_ status: BuildStatus.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .success: "success"
        case .building: "building"
        case .pending: "pending"
        case .failure: "failure"
        }
    }

    private static func decodeStatus(_ raw: String) -> BuildStatus.Status? {
        switch raw {
        case "unknown": .unknown
        case "success": .success
        case "building": .building
        case "pending": .pending
        case "failure": .failure
        default: nil
        }
    }

    private static func encodeSource(_ source: BuildStatus.Source) -> String {
        switch source {
        case .actions: "actions"
        case .commitStatus: "commitStatus"
        case .combined: "combined"
        }
    }

    private static func decodeSource(_ raw: String) -> BuildStatus.Source? {
        switch raw {
        case "actions": .actions
        case "commitStatus": .commitStatus
        case "combined": .combined
        default: nil
        }
    }
}

// MARK: - Repository Persistence

/// UserDefaults-backed persistence for accounts, repositories, cached statuses,
/// and data-schema migration. Stateless — all methods are static so `AppState`
/// stays a thin coordinator over the stored data.
enum RepositoryPersistence {
    private static let currentDataSchemaVersion = 2

    // MARK: Accounts

    static func loadAccounts() -> [Account]? {
        guard let data = UserDefaults.standard.data(forKey: "accounts"),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else { return nil }
        return decoded
    }

    static func save(accounts: [Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "accounts")
        }
    }

    // MARK: Repositories

    static func loadRepositories() -> [Repository]? {
        guard let data = UserDefaults.standard.data(forKey: "repositories"),
              let decoded = try? JSONDecoder().decode([Repository].self, from: data) else { return nil }
        return decoded
    }

    static func save(repositories: [Repository]) {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: "repositories")
        }
    }

    // MARK: Cached statuses

    static func save(cachedStatuses entries: [CachedRepoStatus]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "cachedStatuses")
        }
    }

    /// Decode persisted cached statuses, dropping corrupt or incompatible-version
    /// entries individually so one bad entry doesn't nuke the whole cache.
    /// `hasConfiguredRepos` only affects a diagnostic warning when data is absent.
    static func loadCachedStatuses(hasConfiguredRepos: Bool) -> [CachedRepoStatus] {
        guard let data = UserDefaults.standard.data(forKey: "cachedStatuses") else {
            if hasConfiguredRepos {
                logger.warning("cachedStatuses missing despite configured repos — possible container reset; first poll will seed baseline without notifying")
            }
            return []
        }

        guard let rawArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            logger.warning("cachedStatuses decode failed — first poll will seed baseline without notifying")
            return []
        }

        let decoder = JSONDecoder()
        var cached: [CachedRepoStatus] = []
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
            cached.append(entry)
        }
        if dropped > 0 {
            logger.warning("Dropped \(dropped) cached status entries with incompatible version or corrupt data")
        }
        return cached
    }

    // MARK: Data schema versioning

    static func migrateIfNeeded() {
        let storedVersion = UserDefaults.standard.integer(forKey: "dataSchemaVersion")
        let current = currentDataSchemaVersion

        if storedVersion > current {
            logger.warning("Data schema version \(storedVersion) is newer than current \(current) — attempting to load anyway")
            return
        }

        if storedVersion < current {
            migrateData(from: storedVersion)
        }

        UserDefaults.standard.set(current, forKey: "dataSchemaVersion")
    }

    private static func migrateData(from oldVersion: Int) {
        var version = oldVersion
        while version < currentDataSchemaVersion {
            switch version {
            case 0:
                // Version 0 → 1: Initial schema marker. No data transformation needed —
                // existing UserDefaults keys (accounts, repositories, pollInterval) are
                // already in the correct format.
                logger.info("Migrating data schema from version 0 to 1")
            case 1:
                // Version 1 → 2: Added `isMissing` to Repository. The custom Codable
                // decoder defaults absent values to false, so no data transformation
                // is needed here — just bump the marker.
                logger.info("Migrating data schema from version 1 to 2")
            default:
                logger.warning("Unknown data schema version \(version) — skipping migration step")
            }
            version += 1
        }
    }
}
