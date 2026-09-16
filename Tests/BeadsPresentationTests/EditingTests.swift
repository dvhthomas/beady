import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// An in-memory beads database for presentation tests: loads what it holds, applies writes
/// directly. (`BeadsCore.Issue` spelled out because Swift Testing also has an `Issue`.)
final class MemoryStore: BeadsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var issues: [IssueID: BeadsCore.Issue]
    private var _applied: [IssueChange] = []
    private var _applyStarted = false
    private var gate: CheckedContinuation<Void, Never>?
    var failure: Error?
    /// When set, `apply` waits for `release()`, so tests can act while a write is in flight.
    var holdsApply = false

    init(_ issues: [BeadsCore.Issue]) {
        self.issues = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
    }

    var applied: [IssueChange] { lock.withLock { _applied } }
    var applyStarted: Bool { lock.withLock { _applyStarted } }

    /// Simulates another session writing.
    func setTitle(_ id: IssueID, _ title: String) {
        lock.withLock { issues[id]?.title = title }
    }

    func add(_ issue: BeadsCore.Issue) {
        lock.withLock { issues[issue.id] = issue }
    }

    func release() {
        let waiting = lock.withLock {
            defer { gate = nil }
            return gate
        }
        waiting?.resume()
    }

    func loadSnapshot() async throws -> IssueSnapshot {
        lock.withLock { IssueSnapshot(issues: Array(issues.values)) }
    }

    func changeToken() async -> String { lock.withLock { "\(_applied.count)" } }

    func recentActivity(since: Date) async throws -> ActivityLog { .empty }

    func currentIssue(_ id: IssueID) async throws -> BeadsCore.Issue? { lock.withLock { issues[id] } }

    func issuesCreated(titled title: String, since: Date) async throws -> [BeadsCore.Issue] {
        lock.withLock { issues.values.filter { $0.title == title } }
    }

    func apply(_ change: IssueChange) async throws -> IssueID {
        if holdsApply {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    _applyStarted = true
                    gate = continuation
                }
            }
        }
        return try lock.withLock {
            if let failure { throw failure }
            _applied.append(change)
            switch change {
            case .edit(let id, let edit):
                if let title = edit.title { issues[id]?.title = title }
                if let priority = edit.priority { issues[id]?.priority = priority }
                return id
            case .setStatus(let id, _, let to, let reason):
                issues[id]?.status = to
                issues[id]?.closeReason = reason
                return id
            case .setParent(let id, _, let to):
                issues[id]?.parentID = to
                return id
            case .create(let new):
                let id = IssueID("new-\(issues.count)")
                issues[id] = makeIssue(id, type: new.type, parent: new.parent)
                issues[id]?.title = new.title
                return id
            }
        }
    }

    func commandPreview(for change: IssueChange) -> [String] {
        if case .setStatus(let id, _, let to, let reason) = change {
            return ["bd status \(id) \(to) reason=\(reason ?? "-")"]
        }
        return ["bd change"]
    }
}

@MainActor
func waitUntil(seconds: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
@Suite("Editing through the workspace model")
struct EditingTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        let store = MemoryStore([
            makeIssue("epic", type: "epic"),
            makeIssue("epic.1", parent: "epic"),
            makeIssue("epic.1.1", parent: "epic.1"),
            makeIssue("other", type: "epic"),
            makeIssue("done", status: "closed", closed: t0),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return (model, store)
    }

    @Test("editing is available as soon as a workspace is open; the confirmation sheet is the gate")
    func editingAlwaysAvailable() async {
        let (model, store) = await makeModel()
        #expect(model.canEdit)
        model.propose(.edit("epic.1", IssueEdit(title: "x")))
        #expect(model.pendingChange != nil)
        #expect(store.applied.isEmpty, "still nothing written until confirmed")
    }

    @Test("a bead another session touched recently is flagged, but not blocked")
    func recentActivityWarns() async throws {
        let (model, _) = await makeModel()
        model.noteActivity(ActivityLog(entries: [
            ActivityEntry(issueID: "epic.1", actor: "agent-7", date: t0 - 60, field: "status"),
        ]))
        let summary = try #require(model.recentChange(to: "epic.1"))
        #expect(summary.actor == "agent-7")

        model.propose(.edit("epic.1", IssueEdit(title: "Renamed")))
        let pending = try #require(model.pendingChange)
        #expect(pending.problems.map(\.code) == [.recentlyChangedElsewhere])
        #expect(pending.problems.allSatisfy { $0.severity == .warning })
        #expect(pending.canConfirm, "a warning, not a block: bd has no lease to enforce")

        model.propose(.edit("other", IssueEdit(title: "Untouched")))
        #expect(model.pendingChange?.problems.isEmpty == true)
    }

    @Test("our own writes aren't mistaken for another session")
    func ownWritesAreNotOtherSessions() async {
        let (model, _) = await makeModel()
        model.proposeStatusMove("epic.1.1", to: .done)
        model.pendingReason = "shipped"
        await model.confirmPendingChange()
        model.noteActivity(ActivityLog(entries: [
            ActivityEntry(issueID: "epic.1.1", actor: "Dylan Thomas", date: t0, field: "status"),
        ]))
        #expect(model.recentChange(to: "epic.1.1") == nil)
    }

    @Test("a workspace opened without write access can never edit")
    func noWriting() async {
        let model = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a")]), allowsWriting: false, now: { t0 })
        await model.load()
        #expect(!model.canEdit)
        model.propose(.edit("a", IssueEdit(title: "x")))
        #expect(model.pendingChange == nil)
    }

    @Test("a proposal names the beads involved, lists problems and the exact commands, before writing")
    func proposalPreview() async throws {
        let (model, store) = await makeModel()
        model.propose(.setParent("epic.1", from: "epic", to: "other"))
        let pending = try #require(model.pendingChange)
        #expect(pending.summary == "Move epic.1 to other")
        #expect(pending.subject == "epic.1 · Issue epic.1")
        #expect(pending.details == ["Parent: epic “Issue epic” → other “Issue other”"])
        #expect(pending.problems.isEmpty)
        #expect(model.pendingCommands == ["bd change"])
        #expect(pending.canConfirm)
        #expect(store.applied.isEmpty)
    }

    @Test("errors block confirmation; warnings don't")
    func problemsGateConfirmation() async {
        let (model, _) = await makeModel()
        model.propose(.setParent("epic", from: nil, to: "epic.1"))
        #expect(model.pendingChange?.canConfirm == false)
        model.cancelPendingChange()
        model.propose(.setStatus("epic.1", from: "open", to: "closed", reason: "done"))
        #expect(model.pendingChange?.problems.map(\.code) == [.closesWithOpenChildren])
        #expect(model.pendingChange?.canConfirm == true)
    }

    @Test("moving to a lifecycle proposes its status and asks for a reason when closing")
    func statusMove() async {
        let (model, _) = await makeModel()
        model.proposeStatusMove("epic.1", to: .done)
        #expect(model.pendingChange?.change == .setStatus("epic.1", from: "open", to: "closed", reason: nil))
        #expect(model.pendingChange?.details == ["Status: Open → Closed"])
        #expect(model.pendingChange?.asksForReason == true)
        model.pendingReason = "shipped"
        #expect(model.pendingCommands == ["bd status epic.1 closed reason=shipped"])
    }

    @Test("closing needs a reason before it can be applied")
    func closeNeedsReason() async {
        let (model, _) = await makeModel()
        model.proposeStatusMove("epic.1.1", to: .done)
        #expect(model.pendingChange?.problems.map(\.code) == [.missingCloseReason])
        #expect(model.pendingChange?.canConfirm == false)
        model.pendingReason = "shipped"
        #expect(model.pendingChange?.problems.isEmpty == true)
        #expect(model.pendingChange?.canConfirm == true)
    }

    @Test("dropping a card on a board column proposes that column's value, for whatever the board is grouped by")
    func boardDrops() async {
        let (model, _) = await makeModel()
        model.source = .lifecycle(.all)
        model.layout = .board

        model.grouping = .status
        #expect(model.proposeDrop("epic.1", onGroup: "blocked"))
        #expect(model.pendingChange?.change == .setStatus("epic.1", from: "open", to: "blocked", reason: nil))
        model.cancelPendingChange()

        model.grouping = .category
        #expect(model.proposeDrop("epic.1", onGroup: StatusCategory.done.rawValue))
        #expect(model.pendingChange?.change == .setStatus("epic.1", from: "open", to: "closed", reason: nil))
        model.cancelPendingChange()

        model.grouping = .priority
        #expect(model.proposeDrop("epic.1", onGroup: "0"))
        #expect(model.pendingChange?.change == .edit("epic.1", IssueEdit(priority: 0)))
        model.cancelPendingChange()

        model.grouping = .parent
        #expect(model.proposeDrop("epic.1", onGroup: "other"))
        #expect(model.pendingChange?.change == .setParent("epic.1", from: "epic", to: "other"))
        model.cancelPendingChange()
        #expect(model.proposeDrop("epic.1", onGroup: ""))
        #expect(model.pendingChange?.change == .setParent("epic.1", from: "epic", to: nil))
        model.cancelPendingChange()

        model.grouping = .type
        #expect(!model.proposeDrop("epic.1", onGroup: "bug"))
        #expect(model.pendingChange == nil)
    }

    @Test("dropping a card on its own column proposes nothing")
    func dropOnSameColumn() async {
        let (model, _) = await makeModel()
        model.source = .lifecycle(.all)
        model.grouping = .status
        #expect(!model.proposeDrop("epic.1", onGroup: "open"))
        #expect(model.pendingChange == nil)
    }

    @Test("board columns include every value you could drop into")
    func boardColumnsWhileEditing() async {
        let (model, _) = await makeModel()
        model.source = .lifecycle(.all)
        model.layout = .board
        model.grouping = .category
        #expect(model.boardGroups.map(\.key) == ["active", "wip", "frozen", "done"])
        model.grouping = .status
        #expect(model.boardGroups.map(\.key) == ["open", "blocked", "in_progress", "deferred", "closed"])

        model.source = .lifecycle(.inFlight)
        model.grouping = .status
        #expect(model.boardGroups.map(\.key) == ["blocked", "in_progress"])
    }

    @Test("a board with no grouping falls back to lifecycle columns")
    func boardNeedsColumns() async {
        let (model, _) = await makeModel()
        model.source = .lifecycle(.all)
        model.grouping = .none
        // Editing is always available now, so every column you could drop into is shown,
        // including the ones this database has nothing in yet.
        #expect(model.boardGroups.map(\.key) == ["active", "wip", "frozen", "done"])
    }

    @Test("confirming runs the safe write, reloads, selects the issue and logs the outcome")
    func confirmSuccess() async {
        let (model, store) = await makeModel()
        model.proposeStatusMove("epic.1.1", to: .done)
        model.pendingReason = "shipped"
        await model.confirmPendingChange()
        #expect(store.applied == [.setStatus("epic.1.1", from: "open", to: "closed", reason: "shipped")])
        #expect(model.pendingChange == nil)
        #expect(model.snapshot?.issue("epic.1.1")?.status == "closed")
        #expect(model.selection == "epic.1.1")
        #expect(model.activity.first?.succeeded == true)
    }

    @Test("a failed write keeps the sheet open with the reason, and logs it")
    func confirmFailure() async {
        let (model, store) = await makeModel()
        store.failure = LoadFailure()
        model.propose(.edit("epic.1", IssueEdit(title: "Renamed")))
        await model.confirmPendingChange()
        #expect(model.pendingChange?.failure == "bd exploded")
        #expect(model.pendingChange?.canConfirm == false)
        #expect(model.activity.first?.succeeded == false)
    }

    @Test("while a change is being written, cancel and new proposals are ignored")
    func lockedWhileWriting() async throws {
        let (model, store) = await makeModel()
        store.holdsApply = true
        model.propose(.setParent("epic.1", from: "epic", to: "other"))
        let writing = try #require(model.pendingChange?.id)
        let confirm = Task { await model.confirmPendingChange() }
        #expect(await waitUntil { store.applyStarted })

        model.cancelPendingChange()
        model.propose(.edit("other", IssueEdit(title: "Sneaky")))
        #expect(model.pendingChange?.id == writing)
        #expect(model.pendingChange?.isApplying == true)
        #expect(model.isWriting)

        store.release()
        await confirm.value
        #expect(model.pendingChange == nil)
        #expect(!model.isWriting)
        #expect(store.applied == [.setParent("epic.1", from: "epic", to: "other")])
    }

    @Test("checks are re-run at confirm; if they changed, nothing is written until you look again")
    func problemsRecheckedAtConfirm() async {
        let (model, store) = await makeModel()
        model.propose(.setStatus("epic.1.1", from: "open", to: "closed", reason: "done"))
        #expect(model.pendingChange?.problems.isEmpty == true)
        store.add(makeIssue("epic.1.1.1", parent: "epic.1.1"))
        await model.load()
        await model.confirmPendingChange()
        #expect(store.applied.isEmpty)
        #expect(model.pendingChange?.problems.map(\.code) == [.closesWithOpenChildren])
        #expect(model.pendingChange?.notice != nil)
        await model.confirmPendingChange()
        #expect(store.applied.count == 1, "confirming again after seeing the new warning proceeds")
    }

    @Test("an edit keeps the version it started from, so a refresh in between can't hide a conflict")
    func editBaseSurvivesRefresh() async throws {
        let (model, store) = await makeModel()
        let started = try #require(model.snapshot?.issue("epic.1"))
        store.setTitle("epic.1", "Agent's title")
        await model.load()
        model.propose(.edit("epic.1", IssueEdit(title: "Mine")), basedOn: started)
        await model.confirmPendingChange()
        #expect(model.pendingChange?.failure != nil)
        #expect(store.applied.isEmpty)
        #expect(model.snapshot?.issue("epic.1")?.title == "Agent's title")
    }

    @Test("creating selects the new bead once it's verified")
    func createSelectsNewBead() async throws {
        let (model, _) = await makeModel()
        model.propose(.create(NewIssue(title: "Brand new", parent: "epic")))
        #expect(model.pendingChange?.summary == "Create task “Brand new”")
        #expect(model.pendingChange?.details == ["Title: Brand new", "Type: task · P2", "Parent: epic “Issue epic”"])
        await model.confirmPendingChange()
        let selected = try #require(model.selectedIssue)
        #expect(selected.title == "Brand new")
        #expect(selected.parentID == "epic")
    }

    @Test("a bead created under a labelled parent says it will inherit those labels")
    func createInheritsLabels() async {
        let (model, store) = await makeModel()
        store.add(makeIssue("lane", type: "epic", labels: ["lane", "plan-023"]))
        await model.load()
        model.propose(.create(NewIssue(title: "Child", parent: "lane")))
        #expect(model.pendingChange?.details.last == "Labels: inherits lane, plan-023 from the parent")
    }

    @Test("edit details show old and new values for each changed field")
    func editDetails() async {
        let (model, _) = await makeModel()
        model.propose(.edit("epic.1", IssueEdit(title: "Renamed", priority: 1)))
        #expect(model.pendingChange?.summary == "Edit epic.1")
        #expect(model.pendingChange?.details == ["Title: “Issue epic.1” → “Renamed”", "Priority: P2 → P1"])
    }
}

@Suite("Drag payload")
struct DragPayloadTests {
    @Test("only this app's single-issue payloads are accepted")
    func payload() {
        let encoded = IssueDragPayload.encode("demo-1")
        #expect(IssueDragPayload.decode([encoded]) == "demo-1")
        #expect(IssueDragPayload.decode(["demo-1"]) == nil, "plain text dragged from elsewhere")
        #expect(IssueDragPayload.decode([encoded, IssueDragPayload.encode("demo-2")]) == nil)
        #expect(IssueDragPayload.decode([]) == nil)
        #expect(IssueDragPayload.decode([IssueDragPayload.encode("")]) == nil)
    }
}
