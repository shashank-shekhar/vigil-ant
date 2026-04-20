import Testing
import Foundation
@testable import CIStatusKit

// MARK: - Helpers

/// Build a JSON-serialized array of entry dictionaries for UserDefaults-style storage.
private func makeBlob(_ entries: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: entries)
}

/// A well-formed v1 entry dictionary.
private func goodEntry(
    repoID: Int = 1,
    status: String = "success",
    source: String = "actions",
    version: Int? = CachedRepoStatus.currentVersion
) -> [String: Any] {
    var dict: [String: Any] = [
        "repoID": repoID,
        "statusRaw": status,
        "buildURL": "https://example.com/build/\(repoID)",
        "updatedAt": 725846400.0, // some stable Date timeInterval
        "sourceRaw": source
    ]
    if let version {
        dict["version"] = version
    }
    return dict
}

// MARK: - Tests

@Suite struct CachedStatusStoreTests {

    @Test func nilDataReturnsEmpty() {
        let result = CachedStatusStore.decode(nil)
        #expect(result.entries.isEmpty)
        #expect(result.droppedCount == 0)
        #expect(result.blobCorrupt == false)
    }

    @Test func corruptJSONIsIgnoredAndDoesNotCrash() {
        let garbage = Data("this is not JSON at all {{{".utf8)
        let result = CachedStatusStore.decode(garbage)
        #expect(result.entries.isEmpty)
        #expect(result.blobCorrupt == true)
    }

    @Test func topLevelObjectInsteadOfArrayMarkedCorrupt() {
        // Valid JSON, but not an array of entries — must be treated as corrupt.
        let notAnArray = try! JSONSerialization.data(withJSONObject: ["foo": "bar"])
        let result = CachedStatusStore.decode(notAnArray)
        #expect(result.entries.isEmpty)
        #expect(result.blobCorrupt == true)
    }

    @Test func emptyArrayYieldsEmptyResult() {
        let blob = makeBlob([])
        let result = CachedStatusStore.decode(blob)
        #expect(result.entries.isEmpty)
        #expect(result.droppedCount == 0)
        #expect(result.blobCorrupt == false)
    }

    @Test func preV1EntryMissingVersionIsAcceptedAsV1() {
        // Entry without a `version` field (legacy data written before the field existed).
        let blob = makeBlob([goodEntry(repoID: 42, version: nil)])
        let result = CachedStatusStore.decode(blob)

        #expect(result.blobCorrupt == false)
        #expect(result.droppedCount == 0)
        #expect(result.entries.count == 1)
        let entry = result.entries[0]
        #expect(entry.repoID == 42)
        #expect(entry.version == nil)
        #expect(entry.effectiveVersion == CachedRepoStatus.currentVersion)

        // And it must decode back into a usable BuildStatus.
        let restored = entry.toBuildStatus()
        #expect(restored != nil)
        #expect(restored?.status == .success)
    }

    @Test func futureVersionIsDropped() {
        let futureVersion = CachedRepoStatus.currentVersion + 99
        let blob = makeBlob([goodEntry(repoID: 1, version: futureVersion)])
        let result = CachedStatusStore.decode(blob)

        #expect(result.blobCorrupt == false)
        #expect(result.entries.isEmpty)
        #expect(result.droppedCount == 1)
    }

    @Test func mixOfGoodAndBadEntriesKeepsGoodDropsBad() {
        let blob = makeBlob([
            // good — explicit v1
            goodEntry(repoID: 1, status: "failure", source: "actions"),
            // good — pre-v1 (missing version)
            goodEntry(repoID: 2, status: "success", source: "commitStatus", version: nil),
            // bad — future version
            goodEntry(repoID: 3, version: 9999),
            // bad — missing required field (statusRaw)
            [
                "version": CachedRepoStatus.currentVersion,
                "repoID": 4,
                // "statusRaw" intentionally omitted
                "buildURL": "https://example.com/b/4",
                "updatedAt": 725846400.0,
                "sourceRaw": "actions"
            ] as [String: Any],
            // bad — wrong type for a required field
            [
                "version": CachedRepoStatus.currentVersion,
                "repoID": "not-an-int",
                "statusRaw": "success",
                "buildURL": "https://example.com/b/5",
                "updatedAt": 725846400.0,
                "sourceRaw": "actions"
            ] as [String: Any],
            // good — another explicit v1
            goodEntry(repoID: 6, status: "building", source: "combined")
        ])

        let result = CachedStatusStore.decode(blob)

        #expect(result.blobCorrupt == false)
        #expect(result.entries.count == 3)
        #expect(result.droppedCount == 3)

        let keptIDs = Set(result.entries.map(\.repoID))
        #expect(keptIDs == [1, 2, 6])

        // The pre-v1 entry should still round-trip into a BuildStatus.
        let preV1 = result.entries.first { $0.repoID == 2 }
        #expect(preV1?.toBuildStatus()?.status == .success)
        #expect(preV1?.toBuildStatus()?.source == .commitStatus)
    }

    @Test func missingRequiredFieldDropsEntry() {
        // Missing `updatedAt` — JSONDecoder will reject this as a keyNotFound error.
        let badEntry: [String: Any] = [
            "version": CachedRepoStatus.currentVersion,
            "repoID": 1,
            "statusRaw": "success",
            "buildURL": "https://example.com/b/1",
            "sourceRaw": "actions"
        ]
        let result = CachedStatusStore.decode(makeBlob([badEntry]))
        #expect(result.entries.isEmpty)
        #expect(result.droppedCount == 1)
        #expect(result.blobCorrupt == false)
    }

    @Test func unknownStatusRawDecodedButToBuildStatusReturnsNil() {
        // The raw entry decodes (the struct just stores a string), but
        // converting to BuildStatus yields nil when the enum string is unknown.
        let blob = makeBlob([goodEntry(repoID: 1, status: "bogus-status")])
        let result = CachedStatusStore.decode(blob)
        #expect(result.entries.count == 1)
        #expect(result.entries[0].toBuildStatus() == nil)
    }

    @Test func roundTripEncodeDecodePreservesFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let original = BuildStatus(
            status: .failure,
            buildURL: URL(string: "https://example.com/run/123")!,
            updatedAt: now,
            source: .actions,
            duration: 42.5
        )
        let entry = CachedRepoStatus(repoID: 99, status: original)
        let encoded = try! JSONEncoder().encode([entry])

        let result = CachedStatusStore.decode(encoded)
        #expect(result.entries.count == 1)
        #expect(result.droppedCount == 0)

        let restored = result.entries[0].toBuildStatus()
        #expect(restored?.status == .failure)
        #expect(restored?.buildURL?.absoluteString == "https://example.com/run/123")
        #expect(restored?.source == .actions)
        #expect(restored?.duration == 42.5)
        // Date equality through JSON round-trip with the default encoding strategy
        // (seconds since reference) — both sides use the same strategy.
        #expect(restored?.updatedAt.timeIntervalSince1970 == now.timeIntervalSince1970)
    }

    @Test func entryConstructorTagsCurrentVersion() {
        let s = BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions, duration: nil)
        let entry = CachedRepoStatus(repoID: 1, status: s)
        #expect(entry.version == CachedRepoStatus.currentVersion)
        #expect(entry.effectiveVersion == CachedRepoStatus.currentVersion)
    }
}
