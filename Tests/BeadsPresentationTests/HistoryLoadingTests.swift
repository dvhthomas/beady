import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// A store whose per-bead histories are scripted, with a gate so a read can be held mid-flight.
/// Loads one fixed snapshot; writes fail, as `StubStore`'s do.
final class HistoryStore: BeadsStore, @unchecked Sendable {
    private let lock = NSLock()
    private let issues: [BeadsCore.Issue]
    /// What `versions(of:limit:)` serves, or throws, for every bead.
    var versionsResult: Result<[IssueVersion], Error> = .success([])
    /// When true, `versions` waits for `release()`, so tests can act while history is loading.
    var holdsVersions = false
    private var gate: CheckedContinuation<Void, Never>?
    private var _versionsRequests: [String] = []
    private var _activityRequests: [Date] = []
    /// What the interaction log reports, when it is asked.
    var interactions: ActivityLog = .empty
    var journal: JournalStatus = .unsupported(nil)
    var journalReads: [Result<JournalRead, Error>] = []

    init(_ issues: [BeadsCore.Issue]) { self.issues = issues }

    /// Each request as "id limit", in order.
    var versionsRequests: [String] { lock.withLock { _versionsRequests } }
    /// Every `since` passed to `recentActivity`, in order.
    var activityRequests: [Date] { lock.withLock { _activityRequests } }

    func release() {
        let waiting = lock.withLock {
            defer { gate = nil }
            return gate
        }
        waiting?.resume()
    }

    func versions(of id: IssueID, limit: Int) async throws -> [IssueVersion] {
        let hold = lock.withLock {
            _versionsRequests.append("\(id.rawValue) \(limit)")
            return holdsVersions
        }
        if hold {
            await withCheckedContinuation { continuation in
                lock.withLock { gate = continuation }
            }
        }
        return try versionsResult.get()
    }

    func recentActivity(since: Date) async throws -> ActivityLog {
        lock.withLock {
            _activityRequests.append(since)
            return interactions
        }
    }

    func loadSnapshot() async throws -> IssueSnapshot { IssueSnapshot(issues: issues) }
    func changeToken() async -> String { "t0" }
    func journalStatus() async -> JournalStatus { lock.withLock { journal } }
    func journalRecords(after checkpoint: Int64) async throws -> JournalRead {
        try lock.withLock {
            journalReads.isEmpty ? .success(.records([])) : journalReads.removeFirst()
        }.get()
    }

    func writeJournalSettings(_ settings: [ConfigSetting]) async throws {}
    func journalCommandPreview(_ settings: [ConfigSetting]) -> [String] { [] }
    func backupStatus() async throws -> BackupStatus { .none }
    func configureBackup(folder: String) async throws {}
    func syncBackup() async throws {}
    func currentIssue(_ id: IssueID) async throws -> BeadsCore.Issue? { nil }
    func issuesCreated(titled title: String, since: Date) async throws -> [BeadsCore.Issue] { [] }
    func apply(_ change: IssueChange) async throws -> IssueID { throw ReadOnlyStoreError() }
    func commandPreview(for change: IssueChange) -> [String] { [] }
}

@MainActor
@Suite("Loading one bead's history on demand")
struct HistoryLoadingTests {
    /// Created at t0−300, started at t0−120 by agent-7 (per the interaction log).
    var versions: [IssueVersion] {
        [
            IssueVersion(date: t0 - 120, issue: makeIssue("demo-1", title: "First title", status: "in_progress")),
            IssueVersion(date: t0 - 300, issue: makeIssue("demo-1", title: "First title")),
        ]
    }

    func makeModel(_ store: HistoryStore) async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return model
    }

    @Test("history starts empty and loads into field-level events, newest first, naming who the log matched")
    func happyPath() async {
        let store = HistoryStore([makeIssue("demo-1")])
        store.versionsResult = .success(versions)
        store.interactions = ActivityLog(entries: [
            ActivityEntry(issueID: "demo-1", actor: "agent-7", date: t0 - 120, field: "status"),
        ])
        let model = await makeModel(store)
        #expect(model.history["demo-1"] == nil, "nothing is read until the expander asks")

        await model.loadHistory(for: "demo-1")
        #expect(store.versionsRequests == ["demo-1 50"], "one read, with the default limit")
        #expect(model.history["demo-1"] == .loaded([
            HistoryEvent(date: t0 - 120, field: "status", from: "open", to: "in_progress", actor: "agent-7"),
            HistoryEvent(date: t0 - 300, field: "created", from: "", to: "First title", actor: nil),
        ]))
    }

    @Test("the activity window spans what history shows: a minute before its oldest version")
    func activityWindowFollowsHistory() async {
        let store = HistoryStore([makeIssue("demo-1")])
        store.versionsResult = .success(versions)
        let model = await makeModel(store)
        #expect(store.activityRequests == [t0 - 600], "load() reads the last few minutes")

        await model.loadHistory(for: "demo-1", limit: 7)
        #expect(store.versionsRequests == ["demo-1 7"], "the caller's limit is passed through")
        #expect(store.activityRequests == [t0 - 600, t0 - 360], "then history asks back to t0−300 − 60")
    }

    @Test("a history that can't be read shows the error, per bead")
    func failure() async {
        let store = HistoryStore([makeIssue("demo-1"), makeIssue("demo-2")])
        store.versionsResult = .failure(LoadFailure())
        let model = await makeModel(store)
        await model.loadHistory(for: "demo-1")
        #expect(model.history["demo-1"] == .failed("bd exploded"))
        #expect(model.history["demo-2"] == nil, "only the bead that was asked for")
    }

    @Test("while one read is in flight, asking again does nothing")
    func loadingGuard() async {
        let store = HistoryStore([makeIssue("demo-1")])
        store.versionsResult = .success(versions)
        store.holdsVersions = true
        let model = await makeModel(store)

        let first = Task { await model.loadHistory(for: "demo-1") }
        #expect(await waitUntil { store.versionsRequests.count == 1 })
        #expect(model.history["demo-1"] == .loading)

        await model.loadHistory(for: "demo-1")
        #expect(store.versionsRequests.count == 1, "the second ask was swallowed by the guard")

        store.holdsVersions = false
        store.release()
        await first.value
        #expect(model.history["demo-1"] == .loaded([
            HistoryEvent(date: t0 - 120, field: "status", from: "open", to: "in_progress", actor: nil),
            HistoryEvent(date: t0 - 300, field: "created", from: "", to: "First title", actor: nil),
        ]), "the held read still lands")
    }

    @Test("with the journal on, history is attributed from it and the interaction log is never read")
    func journalActivity() async {
        let store = HistoryStore([makeIssue("demo-1")])
        store.journal = .supported(
            BeadsVersion(1, 3, 0), JournalSettings(isEnabled: true, retainDays: 1, retainRows: 1_000)
        )
        store.journalReads = [.success(.records([
            JournalRecord(seq: 1, date: t0 - 30, op: "create", issueID: "demo-1", actor: "agent-7"),
        ]))]
        store.versionsResult = .success([
            IssueVersion(date: t0 - 30, issue: makeIssue("demo-1", title: "Fresh bead")),
        ])
        // A decoy: if loadHistory wrongly read the interaction log, this actor would win.
        store.interactions = ActivityLog(entries: [
            ActivityEntry(issueID: "demo-1", actor: "from-interactions", date: t0 - 30, field: "created"),
        ])
        let model = await makeModel(store)
        #expect(model.journal.isOn)

        await model.loadHistory(for: "demo-1")
        #expect(model.history["demo-1"] == .loaded([
            HistoryEvent(date: t0 - 30, field: "created", from: "", to: "Fresh bead", actor: "agent-7"),
        ]))
        #expect(store.activityRequests.isEmpty, "the journal answered; the log was never asked")
    }
}
