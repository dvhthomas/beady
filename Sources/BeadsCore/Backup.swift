import Foundation

/// Where a database is backed up to, and when it last went.
///
/// bd does the work — a Dolt-native push that carries tables, branches and history, unlike the
/// JSONL export, which is only the issues. This is what the app reads to say whether anyone
/// would get their beads back.
public struct BackupStatus: Equatable, Sendable {
    public static let none = BackupStatus(destination: nil, lastSync: nil, databaseSize: nil)

    /// A readable path, or nil when no backup is configured.
    public let destination: String?
    public let lastSync: Date?
    /// bd's own wording, e.g. "1.4 MB".
    public let databaseSize: String?

    public init(destination: String?, lastSync: Date?, databaseSize: String?) {
        self.destination = destination
        self.lastSync = lastSync
        self.databaseSize = databaseSize
    }

    public var isConfigured: Bool { destination != nil }

    /// True when a backup is set up but has never actually run.
    public var isConfiguredButNeverRun: Bool { isConfigured && lastSync == nil }
}
