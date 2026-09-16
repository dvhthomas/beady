import Foundation

// BeadsCore: the domain model and read-only queries over a beads snapshot.
// No I/O lives here; outer layers supply data through `IssueSnapshotLoading`.

/// Port through which an outer layer (the bd CLI, a Dolt connection, a fixture)
/// supplies a complete, read-only snapshot of a beads database.
public protocol IssueSnapshotLoading: Sendable {
    func loadSnapshot() async throws -> IssueSnapshot
}

/// The single port through which the app reads and writes a beads database: loading, live reads,
/// writes and change detection all go through one implementation.
public protocol BeadsStore: IssueSnapshotLoading, IssueWriting {
    /// Changes whenever the database may have been written. Cheap enough to call every few seconds.
    func changeToken() async -> String
    /// What has changed in the database since a moment, so the app can tell when another session
    /// is working on the same bead.
    func recentActivity(since: Date) async throws -> ActivityLog
}
