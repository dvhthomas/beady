import BeadsCore
import Foundation
import Testing

/// `Issue` alone is ambiguous with Swift Testing's `Issue`.
private typealias Bead = BeadsCore.Issue

/// An in-memory beads database standing in for bd, with knobs for the ways writes go wrong.
final class FakeWriter: IssueWriting, @unchecked Sendable {
    enum ApplyBehavior {
        case correct
        /// bd exits 0 but nothing changes (e.g. closing something already closed).
        case ignoresChange
        /// The change is committed, then bd reports an error (a timeout after commit, say).
        case failsAfterApplying
        /// Nothing is committed and bd reports an error.
        case failsWithoutApplying
        /// Only `duringApply`'s mutation is committed, then bd reports an error.
        case partiallyApplies
    }

    private let lock = NSLock()
    private var issues: [IssueID: BeadsCore.Issue]
    private var _log: [String] = []
    var behavior: ApplyBehavior = .correct
    /// Runs during the first read, as another session writing concurrently would.
    var concurrentWrite: (@Sendable (inout [IssueID: BeadsCore.Issue]) -> Void)?
    /// Runs inside the write, between the last read and bd committing.
    var duringApply: (@Sendable (inout [IssueID: BeadsCore.Issue]) -> Void)?
    var createdID: IssueID = "new-1"

    init(_ issues: [BeadsCore.Issue]) {
        self.issues = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
    }

    var log: [String] { lock.withLock { _log } }
    func issue(_ id: IssueID) -> BeadsCore.Issue? { lock.withLock { issues[id] } }

    func currentIssue(_ id: IssueID) async throws -> BeadsCore.Issue? {
        lock.withLock {
            _log.append("read \(id)")
            if let concurrentWrite, _log.filter({ $0.hasPrefix("read") }).count == 1 {
                concurrentWrite(&issues)
            }
            return issues[id]
        }
    }

    func issuesCreated(titled title: String, since: Date) async throws -> [BeadsCore.Issue] {
        lock.withLock {
            _log.append("search")
            return issues.values.filter { $0.title == title && $0.createdAt >= since }.sorted { $0.id < $1.id }
        }
    }

    func apply(_ change: IssueChange) async throws -> IssueID {
        try lock.withLock {
            _log.append("apply")
            duringApply?(&issues)
            switch behavior {
            case .failsWithoutApplying, .partiallyApplies:
                throw WriteError()
            case .ignoresChange:
                return change.issueID ?? createdID
            case .correct, .failsAfterApplying:
                let id = mutate(change)
                if behavior == .failsAfterApplying { throw WriteError() }
                return id
            }
        }
    }

    func commandPreview(for change: IssueChange) -> [String] { ["bd fake"] }

    struct WriteError: Error, LocalizedError {
        var errorDescription: String? { "bd exited with status 1" }
    }

    private func mutate(_ change: IssueChange) -> IssueID {
        switch change {
        case .edit(let id, let edit):
            var issue = issues[id]!
            if let title = edit.title { issue.title = title }
            if let description = edit.description { issue.description = description }
            if let notes = edit.notes { issue.notes = notes }
            if let priority = edit.priority { issue.priority = priority }
            issues[id] = issue
            return id
        case .setStatus(let id, _, let to, let reason):
            issues[id]?.status = to
            issues[id]?.closeReason = to == "closed" ? reason : nil
            issues[id]?.closedAt = to == "closed" ? Date() : nil
            return id
        case .setParent(let id, _, let to):
            issues[id]?.parentID = to
            return id
        case .setBlocker(let id, let blocker, let on):
            var dependencies = issues[id]?.dependencies ?? []
            dependencies.removeAll { $0.kind == .blocks && $0.dependsOnID == blocker }
            if on { dependencies.append(Dependency(issueID: id, dependsOnID: blocker, kind: .blocks)) }
            issues[id]?.dependencies = dependencies
            return id
        case .setMark(let id, let mark, let on):
            var labels = issues[id]?.labels ?? []
            labels.removeAll { $0 == mark.label }
            if on { labels.append(mark.label) }
            issues[id]?.labels = labels
            return id
        case .create(let new):
            issues[createdID] = makeIssue(
                createdID, title: new.title, description: new.description,
                priority: new.priority, type: new.type, parent: new.parent, created: Date()
            )
            return createdID
        }
    }
}

@Suite("Change runner: validate, check live state, write, verify")
struct ChangeRunnerTests {
    fileprivate let issues: [Bead] = [
        makeIssue("epic", type: "epic"),
        makeIssue("epic.1", parent: "epic"),
        makeIssue("other", type: "epic"),
        makeIssue("closed-1", status: "closed", closed: t0),
    ]
    var snapshot: IssueSnapshot { IssueSnapshot(issues: issues) }

    /// No settling delay between re-reads in tests.
    func runner(_ writer: FakeWriter) -> ChangeRunner {
        ChangeRunner(writer: writer, settleDelay: .zero)
    }

    func failure(_ body: () async throws -> Void) async -> ChangeFailure? {
        do {
            try await body()
            return nil
        } catch let failure as ChangeFailure {
            return failure
        } catch {
            Testing.Issue.record("unexpected \(error)")
            return nil
        }
    }

    @Test("a valid edit is checked against live data, written once, and verified")
    func happyPath() async throws {
        let writer = FakeWriter(issues)
        let id = try await runner(writer).run(.edit("epic.1", IssueEdit(title: "  Better  ")), seenIn: snapshot)
        #expect(id == "epic.1")
        #expect(writer.issue("epic.1")?.title == "Better")
        #expect(writer.log == ["read epic.1", "apply", "read epic.1"])
    }

    @Test("the parent chain is walked first and the conflict read happens last, right before the write")
    func conflictReadIsLast() async throws {
        let writer = FakeWriter(issues)
        try await runner(writer).run(.setParent("epic.1", from: "epic", to: "other"), seenIn: snapshot)
        #expect(writer.log == ["read other", "read epic.1", "apply", "read epic.1"])
    }

    @Test("invalid changes are rejected before anything is written")
    func rejectedBeforeWrite() async {
        let writer = FakeWriter(issues)
        await #expect(throws: ChangeFailure.self) {
            try await runner(writer).run(.edit("epic.1", IssueEdit(title: "")), seenIn: snapshot)
        }
        #expect(!writer.log.contains("apply"))
    }

    @Test("a concurrent edit to the same field stops the write")
    func concurrentConflict() async {
        let writer = FakeWriter(issues)
        writer.concurrentWrite = { $0["epic.1"]?.title = "Agent's title" }
        let result = await failure { try await runner(writer).run(.edit("epic.1", IssueEdit(title: "Mine")), seenIn: snapshot) }
        guard case .conflict(let conflicts) = result else {
            Testing.Issue.record("expected a conflict, got \(String(describing: result))")
            return
        }
        #expect(conflicts.map(\.field) == ["title"])
        #expect(!writer.log.contains("apply"))
        #expect(writer.issue("epic.1")?.title == "Agent's title")
    }

    @Test("the version an edit started from wins over a newer snapshot")
    func explicitBase() async {
        let writer = FakeWriter(issues)
        var started = issues[1]
        started.title = "Title when editing began"
        await #expect(throws: ChangeFailure.self) {
            try await runner(writer).run(.edit("epic.1", IssueEdit(title: "Mine")), seenIn: snapshot, base: started)
        }
        #expect(!writer.log.contains("apply"))
    }

    @Test("an issue deleted since it was seen stops the write")
    func deletedMeanwhile() async {
        let writer = FakeWriter(issues)
        writer.concurrentWrite = { $0["epic.1"] = nil }
        await #expect(throws: ChangeFailure.issueDisappeared("epic.1")) {
            try await runner(writer).run(.setStatus("epic.1", from: "open", to: "in_progress", reason: nil), seenIn: snapshot)
        }
        #expect(!writer.log.contains("apply"))
    }

    @Test("the cycle check follows the live parent chain, not just the snapshot")
    func liveCycleCheck() async {
        let writer = FakeWriter(issues)
        // Meanwhile someone moved `other` under epic.1, so epic.1 → other would now be a cycle.
        writer.concurrentWrite = { $0["other"]?.parentID = "epic.1" }
        await #expect(throws: ChangeFailure.self) {
            try await runner(writer).run(.setParent("epic.1", from: "epic", to: "other"), seenIn: snapshot)
        }
        #expect(!writer.log.contains("apply"))
        #expect(writer.issue("epic.1")?.parentID == "epic")
    }

    @Test("a write that reports failure but landed cleanly is recognised by re-reading")
    func failedButLanded() async throws {
        let writer = FakeWriter(issues)
        writer.behavior = .failsAfterApplying
        let id = try await runner(writer).run(.setParent("epic.1", from: "epic", to: "other"), seenIn: snapshot)
        #expect(id == "epic.1")
        #expect(writer.issue("epic.1")?.parentID == "other")
    }

    @Test("if someone else also wrote during a failed write, the outcome is reported as uncertain")
    func failedLandedButOthersWrote() async {
        let writer = FakeWriter(issues)
        writer.behavior = .failsAfterApplying
        writer.duringApply = { $0["epic.1"]?.title = "Agent's title" }
        let result = await failure { try await runner(writer).run(.setParent("epic.1", from: "epic", to: "other"), seenIn: snapshot) }
        guard case .uncertain = result else {
            Testing.Issue.record("expected uncertain, got \(String(describing: result))")
            return
        }
    }

    @Test("a write that fails and didn't land is reported as failed, so it's safe to retry")
    func failedWrite() async {
        let writer = FakeWriter(issues)
        writer.behavior = .failsWithoutApplying
        await #expect(throws: ChangeFailure.writeFailed("bd exited with status 1")) {
            try await runner(writer).run(.setParent("epic.1", from: "epic", to: "other"), seenIn: snapshot)
        }
    }

    @Test("a two-step status change that stops halfway reports where the bead actually is")
    func partialStatusChange() async {
        let writer = FakeWriter(issues)
        writer.behavior = .partiallyApplies
        writer.duringApply = { issues in
            issues["closed-1"]?.status = "open"
            issues["closed-1"]?.closedAt = nil
        }
        let result = await failure {
            try await runner(writer).run(.setStatus("closed-1", from: "closed", to: "in_progress", reason: "back"), seenIn: snapshot)
        }
        guard case .uncertain(let id, let detail) = result else {
            Testing.Issue.record("expected uncertain, got \(String(describing: result))")
            return
        }
        #expect(id == "closed-1")
        #expect(detail.contains("open"))
    }

    @Test("a write that claims success but didn't stick fails verification")
    func unverified() async {
        let writer = FakeWriter(issues)
        writer.behavior = .ignoresChange
        let result = await failure {
            try await runner(writer).run(.setStatus("epic.1", from: "open", to: "closed", reason: "done"), seenIn: snapshot)
        }
        guard case .unverified(let id, let mismatches) = result else {
            Testing.Issue.record("expected unverified, got \(String(describing: result))")
            return
        }
        #expect(id == "epic.1")
        #expect(mismatches.map(\.field) == ["status", "close reason"])
    }

    @Test("a close that another session beat us to isn't reported as ours")
    func closedByAnotherSession() async {
        let writer = FakeWriter(issues)
        writer.behavior = .ignoresChange
        writer.duringApply = { issues in
            issues["epic.1"]?.status = "closed"
            issues["epic.1"]?.closeReason = "duplicate, do not ship"
            issues["epic.1"]?.closedAt = Date()
        }
        let result = await failure {
            try await runner(writer).run(.setStatus("epic.1", from: "open", to: "closed", reason: "shipped"), seenIn: snapshot)
        }
        guard case .unverified(_, let mismatches) = result else {
            Testing.Issue.record("expected unverified, got \(String(describing: result))")
            return
        }
        #expect(mismatches.map(\.field) == ["close reason"])
    }

    @Test("creating a bead returns its new id after checking what was stored")
    func create() async throws {
        let writer = FakeWriter(issues)
        writer.createdID = "fresh-1"
        let change = IssueChange.create(NewIssue(title: "New thing", type: "bug", priority: 1, description: "why", parent: "epic"))
        let id = try await runner(writer).run(change, seenIn: snapshot)
        #expect(id == "fresh-1")
        #expect(writer.issue("fresh-1")?.parentID == "epic")
        #expect(writer.log == ["read epic", "apply", "read fresh-1"])
    }

    @Test("a create that reports failure but landed is found, so a retry won't duplicate it")
    func createFailedButLanded() async throws {
        let writer = FakeWriter(issues)
        writer.behavior = .failsAfterApplying
        writer.createdID = "fresh-1"
        let id = try await runner(writer).run(.create(NewIssue(title: "Only once")), seenIn: snapshot)
        #expect(id == "fresh-1")
    }

    @Test("a create that failed and made nothing is a plain failure")
    func createFailed() async {
        let writer = FakeWriter(issues)
        writer.behavior = .failsWithoutApplying
        await #expect(throws: ChangeFailure.writeFailed("bd exited with status 1")) {
            try await runner(writer).run(.create(NewIssue(title: "Never made")), seenIn: snapshot)
        }
    }

    @Test("a failed create that leaves more than one matching bead is uncertain")
    func createAmbiguous() async {
        let writer = FakeWriter(issues + [makeIssue("twin", title: "Twin", created: Date())])
        writer.behavior = .failsAfterApplying
        writer.createdID = "twin-2"
        let result = await failure { try await runner(writer).run(.create(NewIssue(title: "Twin")), seenIn: snapshot) }
        guard case .uncertain(nil, _) = result else {
            Testing.Issue.record("expected uncertain, got \(String(describing: result))")
            return
        }
    }
}
