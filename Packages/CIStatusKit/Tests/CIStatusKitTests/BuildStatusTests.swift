import Testing
import Foundation
@testable import CIStatusKit

@Test func mergeFailureWins() {
    let result = BuildStatus.merge(
        actionsConclusion: "success",
        commitStatusState: "failure",
        actionsURL: URL(string: "https://example.com/actions")!,
        commitStatusURL: URL(string: "https://example.com/ci")!,
        updatedAt: Date()
    )
    #expect(result.status == .failure)
    #expect(result.buildURL?.absoluteString == "https://example.com/ci")
    #expect(result.source == .commitStatus)
}

@Test func mergeBothSuccess() {
    let result = BuildStatus.merge(
        actionsConclusion: "success",
        commitStatusState: "success",
        actionsURL: URL(string: "https://example.com/actions")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .success)
    #expect(result.source == .combined)
}

@Test func mergePendingWhenNoneFailingButOnePending() {
    let result = BuildStatus.merge(
        actionsConclusion: "success",
        commitStatusState: "pending",
        actionsURL: URL(string: "https://example.com/actions")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .pending)
}

@Test func mergeActionsOnlyFailure() {
    let result = BuildStatus.merge(
        actionsConclusion: "failure",
        commitStatusState: nil,
        actionsURL: URL(string: "https://example.com/actions/fail")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .failure)
    #expect(result.buildURL?.absoluteString == "https://example.com/actions/fail")
    #expect(result.source == .actions)
}

@Test func mergeUnknownWhenNoData() {
    let result = BuildStatus.merge(
        actionsConclusion: nil,
        commitStatusState: nil,
        actionsURL: nil,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .unknown)
}

@Test func mergeInProgressMapsToBuilding() {
    let result = BuildStatus.merge(
        actionsConclusion: nil,
        actionsRunStatus: "in_progress",
        commitStatusState: nil,
        actionsURL: URL(string: "https://example.com/actions/run")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .building)
    #expect(result.buildURL?.absoluteString == "https://example.com/actions/run")
    #expect(result.source == .actions)
}

@Test func mergeQueuedMapsToBuilding() {
    let result = BuildStatus.merge(
        actionsConclusion: nil,
        actionsRunStatus: "queued",
        commitStatusState: nil,
        actionsURL: URL(string: "https://example.com/actions/run")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .building)
}

@Test func mergeFailureOverridesBuilding() {
    let result = BuildStatus.merge(
        actionsConclusion: nil,
        actionsRunStatus: "in_progress",
        commitStatusState: "failure",
        actionsURL: URL(string: "https://example.com/actions")!,
        commitStatusURL: URL(string: "https://example.com/ci")!,
        updatedAt: Date()
    )
    #expect(result.status == .failure)
    #expect(result.buildURL?.absoluteString == "https://example.com/ci")
}

@Test func mergeBuildingOverridesSuccess() {
    let result = BuildStatus.merge(
        actionsConclusion: nil,
        actionsRunStatus: "in_progress",
        commitStatusState: "success",
        actionsURL: URL(string: "https://example.com/actions")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .building)
}

@Test func mergeConclusionTakesPriorityOverRunStatus() {
    // When conclusion is present, run status is ignored
    let result = BuildStatus.merge(
        actionsConclusion: "success",
        actionsRunStatus: "completed",
        commitStatusState: nil,
        actionsURL: URL(string: "https://example.com/actions")!,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.status == .success)
}

@Test func buildingSeverityBetweenSuccessAndPending() {
    #expect(BuildStatus.Status.success.severity < BuildStatus.Status.building.severity)
    #expect(BuildStatus.Status.building.severity < BuildStatus.Status.pending.severity)
    #expect(BuildStatus.Status.pending.severity < BuildStatus.Status.failure.severity)
}

@Test func mergeDurationFromRunTiming() {
    let started = Date(timeIntervalSince1970: 1000)
    let updated = Date(timeIntervalSince1970: 1150) // 150 seconds later
    let result = BuildStatus.merge(
        actionsConclusion: "success",
        actionsRunStartedAt: started,
        actionsUpdatedAt: updated,
        commitStatusState: nil,
        actionsURL: nil,
        commitStatusURL: nil,
        updatedAt: updated
    )
    #expect(result.status == .success)
    #expect(result.duration == 150)
}

@Test func mergeDurationNilWithoutRunStartedAt() {
    let result = BuildStatus.merge(
        actionsConclusion: "success",
        commitStatusState: nil,
        actionsURL: nil,
        commitStatusURL: nil,
        updatedAt: Date()
    )
    #expect(result.duration == nil)
}
