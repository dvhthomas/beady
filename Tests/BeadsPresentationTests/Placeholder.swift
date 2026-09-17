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
    func recentActivity(since: Date) async throws -> ActivityLog { .empty }
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
