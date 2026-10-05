import BeadsCore
import Foundation

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func makeIssue(
    _ id: IssueID,
    title: String? = nil,
    status: String = "open",
    priority: Int = 2,
    type: String = "task",
    assignee: String? = nil,
    labels: [String] = [],
    parent: IssueID? = nil,
    updated: Date = t0,
    closed: Date? = nil
) -> Issue {
    Issue(
        id: id, title: title ?? "Issue \(id)", status: status, priority: priority, type: type, assignee: assignee,
        labels: labels, createdAt: t0, updatedAt: updated, closedAt: closed, parentID: parent
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
    private(set) var enabledJournal: [[ConfigSetting]] = []

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

    func enableJournal(_ settings: [ConfigSetting]) async throws {
        lock.withLock {
            enabledJournal.append(settings)
            if case .supported(let version, var current) = journal {
                current.isEnabled = true
                journal = .supported(version, current)
            }
        }
    }

    // Schema upgrades.
    private(set) var skewFlags: [Bool] = []
    private(set) var copies: [(folder: String, schema: Int)] = []
    var copyFailure: Error?
    private(set) var upgrades = 0
    var upgradeFailure: Error?

    func loadSnapshot(ignoringSchemaSkew: Bool) async throws -> IssueSnapshot {
        lock.withLock { skewFlags.append(ignoringSchemaSkew) }
        return try await loadSnapshot()
    }

    func copyDatabase(into folder: String, schema: Int, at date: Date) async throws -> String {
        try lock.withLock {
            if let copyFailure { throw copyFailure }
            copies.append((folder, schema))
            return folder + "/demo-beads-v\(schema)"
        }
    }

    func upgradeSchema() async throws {
        try lock.withLock {
            upgrades += 1
            if let upgradeFailure { throw upgradeFailure }
        }
    }

    func schemaUpgradePreview() -> [String] { ["bd migrate schema"] }

    func journalCommandPreview(_ settings: [ConfigSetting]) -> [String] {
        ["bd config set-many " + settings.map { "\($0.key)=\($0.value)" }.joined(separator: " ")]
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
