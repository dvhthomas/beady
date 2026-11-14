import BeadsCore
import Foundation

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func days(_ n: Double) -> TimeInterval { n * 86_400 }

func makeIssue(
    _ id: IssueID,
    title: String? = nil,
    status: String = "open",
    priority: Int = 2,
    type: String = "task",
    assignee: String? = nil,
    labels: [String] = [],
    parent: IssueID? = nil,
    blockedBy: [IssueID] = [],
    updated: Date = t0,
    closed: Date? = nil,
    deferUntil: Date? = nil
) -> Issue {
    Issue(
        id: id, title: title ?? "Issue \(id)", status: status, priority: priority, type: type, assignee: assignee,
        labels: labels, createdAt: t0, updatedAt: updated, closedAt: closed, deferUntil: deferUntil, parentID: parent,
        dependencies: blockedBy.map { Dependency(issueID: id, dependsOnID: $0, kind: .blocks) }
    )
}

struct LoadFailure: Error, LocalizedError {
    var errorDescription: String? { "bd exploded" }
}

struct ReadOnlyStoreError: Error {}

/// A store for tests that only load. Serves queued results in order, repeating the last; writes fail.
final class StubStore: BeadsStore, @unchecked Sendable {
    private let lock = NSLock()
    var backup: BackupStatus = .none
    private var results: [Result<IssueSnapshot, Error>]
    private var _calls = 0
    private var _token = "t0"
    /// Runs inside each load, for example to simulate a write landing mid-load.
    var onLoad: (@Sendable (StubStore) -> Void)?

    init(_ results: [Result<IssueSnapshot, Error>]) { self.results = results }
    convenience init(_ issues: [Issue]) { self.init([.success(IssueSnapshot(issues: issues))]) }

    var calls: Int { lock.withLock { _calls } }

    func setToken(_ token: String) {
        lock.withLock { _token = token }
    }

    func loadSnapshot() async throws -> IssueSnapshot {
        let (result, hook) = lock.withLock {
            _calls += 1
            return (results.count > 1 ? results.removeFirst() : results[0], onLoad)
        }
        hook?(self)
        return try result.get()
    }

    func changeToken() async -> String { lock.withLock { _token } }
    /// What bd's interaction log reports: the only activity when there's no journal.
    var interactions: ActivityLog = .empty
    func recentActivity(since: Date) async throws -> ActivityLog { interactions }

    // The events journal: off (bd too old) unless a test says otherwise.
    var journal: JournalStatus = .unsupported(nil)
    /// Served in order, then empty reads.
    var journalReads: [Result<JournalRead, Error>] = []
    private(set) var journalStatusChecks = 0
    private(set) var journalCheckpoints: [Int64] = []
    /// Every settings write, in order: Beady's retention when turning it on, the reverse on Undo.
    private(set) var journalWrites: [[ConfigSetting]] = []
    /// Thrown by the next settings write, when a test wants bd to refuse.
    var journalWriteFailure: Error?

    func journalStatus() async -> JournalStatus {
        lock.withLock {
            journalStatusChecks += 1
            return journal
        }
    }

    func journalRecords(after checkpoint: Int64) async throws -> JournalRead {
        try lock.withLock {
            journalCheckpoints.append(checkpoint)
            return journalReads.isEmpty ? .success(.records([])) : journalReads.removeFirst()
        }.get()
    }

    func writeJournalSettings(_ settings: [ConfigSetting]) async throws {
        if let journalWriteFailure { throw journalWriteFailure }
        lock.withLock {
            journalWrites.append(settings)
            if case .supported(let version, var current) = journal {
                for setting in settings {
                    switch setting.key {
                    case "events-journal": current.isEnabled = setting.value == "true"
                    case "events-journal-retain-days": current.retainDays = Int(setting.value)
                    case "events-journal-retain-rows": current.retainRows = Int(setting.value)
                    default: break
                    }
                }
                journal = .supported(version, current)
            }
        }
    }

    func journalCommandPreview(_ settings: [ConfigSetting]) -> [String] {
        ["bd config set-many " + settings.map { "\($0.key)=\($0.value)" }.joined(separator: " ")]
    }
    // Sharing: nothing shared unless a test says otherwise.
    /// What bd reports; nil is a bd that wouldn't say.
    var sharing: SharingFacts? = SharingFacts.none
    var setup = WorkspaceSetup.unknown
    var origin: String?
    /// Served in order by `sync()`, then `.synced`.
    var syncOutcomes: [SyncOutcome] = []
    /// What bd reports after the next successful sync or step, when a test wants the facts to move.
    var sharingAfterAction: SharingFacts?
    /// Every step performed, in order.
    private(set) var sharingSteps: [SharingStep] = []
    private(set) var syncs = 0
    /// Thrown by the step with this index, when a test wants bd to refuse it.
    var stepFailures: [Int: Error] = [:]

    func sharingFacts() async throws -> SharingFacts {
        guard let sharing else { throw LoadFailure() }
        return sharing
    }
    func workspaceSetup() async -> WorkspaceSetup { setup }
    func gitOriginURL() async -> String? { origin }
    /// A sync that keeps running until its task is cancelled, then answers as bd does when
    /// interrupted: a failure whose words say the context was cancelled.
    var syncRunsUntilStopped = false
    /// What a stopped sync answers with; a sync that got there first answers `.synced`.
    var answerWhenStopped: SyncOutcome = .failed("sync failed: push: push to origin/main: Error 1105: unknown push error; context canceled")

    func sync() async throws -> SyncOutcome {
        syncs += 1
        if syncRunsUntilStopped {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return answerWhenStopped
        }
        let outcome = syncOutcomes.isEmpty ? .synced : syncOutcomes.removeFirst()
        if outcome == .synced, let next = sharingAfterAction { sharing = next }
        return outcome
    }
    func perform(_ step: SharingStep) async throws {
        if let failure = stepFailures[sharingSteps.count] {
            sharingSteps.append(step)
            throw failure
        }
        sharingSteps.append(step)
        if let next = sharingAfterAction { sharing = next }
    }
    func commandPreview(for step: SharingStep) -> String {
        switch step {
        case .addRemote(let name, let url, let allow): "bd dolt remote add\(allow ? " --allow-git-origin" : "") -- \(name) \(url)"
        case .publish: "bd dolt push"
        case .sync: "bd sync --json"
        case .settleConflict(let side): "bd dolt pull --strategy=\(side.rawValue)"
        }
    }

    func versions(of id: IssueID, limit: Int) async throws -> [IssueVersion] { [] }
    func backupStatus() async throws -> BackupStatus { backup }
    func configureBackup(folder: String) async throws { backup = BackupStatus(destination: folder, lastSync: t0, databaseSize: "1 KB") }
    func syncBackup() async throws {
        if let destination = backup.destination {
            backup = BackupStatus(destination: destination, lastSync: t0, databaseSize: "1 KB")
        }
    }
    func currentIssue(_ id: IssueID) async throws -> Issue? { nil }
    func issuesCreated(titled title: String, since: Date) async throws -> [Issue] { [] }
    func apply(_ change: IssueChange) async throws -> IssueID { throw ReadOnlyStoreError() }
    func commandPreview(for change: IssueChange) -> [String] { [] }
}

final class Mutable<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
