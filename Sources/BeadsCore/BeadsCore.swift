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
    /// Every recorded version of one bead, oldest or newest first — `History` turns these into
    /// readable changes.
    func versions(of id: IssueID, limit: Int) async throws -> [IssueVersion]
    /// Where this database is backed up, if anywhere.
    func backupStatus() async throws -> BackupStatus
    /// Points bd's backup at a folder, then pushes to it.
    func configureBackup(folder: String) async throws
    /// Pushes to the configured destination.
    func syncBackup() async throws
    /// Whether bd is new enough to keep an events journal here, and whether it does.
    func journalStatus() async -> JournalStatus
    /// Journal records after a checkpoint, oldest first.
    func journalRecords(after checkpoint: Int64) async throws -> JournalRead
    /// Writes the journal's settings to the workspace's bd config: on, or back off.
    func writeJournalSettings(_ settings: [ConfigSetting]) async throws
    /// The exact commands `writeJournalSettings` would run.
    func journalCommandPreview(_ settings: [ConfigSetting]) -> [String]
    /// Where the database is shared, and how it stands against that remote. Asks the remote.
    func sharingFacts() async throws -> SharingFacts
    /// The checkouts, hooks and storage bd reports, for the Workspace Setup sheet.
    func workspaceSetup() async -> WorkspaceSetup
    /// The URL of the repository's git `origin`, if it has one.
    func gitOriginURL() async -> String?
    /// One pull, check and push against the default remote.
    func sync() async throws -> SyncOutcome
    /// Runs one step of setting sharing up or settling a conflict.
    func perform(_ step: SharingStep) async throws
    /// The exact command a step runs.
    func commandPreview(for step: SharingStep) -> String
}

/// The writes behind sharing, each one bd command (plan 0006).
public enum SharingStep: Equatable, Sendable {
    /// `bd dolt remote add`. `allowGitOrigin` is the consent bd asks for when the URL is the
    /// repository's own origin.
    case addRemote(name: String, url: String, allowGitOrigin: Bool)
    /// `bd dolt push`: the first publish, which `bd sync` can't do against an empty remote.
    case publish
    /// `bd sync`, for showing its command; `BeadsStore.sync()` runs it.
    case sync
    /// `bd dolt pull --strategy`, keeping one side of everything bd wouldn't merge.
    case settleConflict(keeping: ConflictSide)
}

/// A store with no journal: the app carries on with the file watcher and the interaction log.
public extension BeadsStore {
    func journalStatus() async -> JournalStatus { .unsupported(nil) }
    func journalRecords(after checkpoint: Int64) async throws -> JournalRead { .records([]) }
    func writeJournalSettings(_ settings: [ConfigSetting]) async throws {}
    func journalCommandPreview(_ settings: [ConfigSetting]) -> [String] { [] }
}

/// A store that shares nothing: a fixture, or a database the app only reads.
public extension BeadsStore {
    func sharingFacts() async throws -> SharingFacts { .none }
    func workspaceSetup() async -> WorkspaceSetup { .unknown }
    func gitOriginURL() async -> String? { nil }
    func sync() async throws -> SyncOutcome { .noRemote }
    func perform(_ step: SharingStep) async throws {}
    func commandPreview(for step: SharingStep) -> String { "" }
}
