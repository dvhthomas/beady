import Foundation

/// The database and this bd disagree about the schema, so bd won't read it.
///
/// bd upgrades a database's schema whenever a write opens it, but Beady reads with `--readonly`,
/// and a read-only open can't upgrade anything. So Beady is often the first to meet a workspace
/// last written by an older bd, and it has to ask before upgrading: the upgrade is one-way, and
/// every older bd still writing there (an agent, CI, another machine) refuses the database after.
public struct SchemaMismatch: Error, Equatable, Sendable, LocalizedError {
    public enum Direction: Equatable, Sendable {
        /// The database is older than this bd, which can upgrade it.
        case behind
        /// A newer bd has upgraded the database; this bd is the one out of date.
        case ahead
    }

    public let direction: Direction
    /// The database's schema version, and the one this bd expects. Schema versions, not bd
    /// releases: bd 1.3.0 expects schema 66.
    public let databaseVersion: Int
    public let bdVersion: Int

    public init(_ direction: Direction, database: Int, bd: Int) {
        self.direction = direction
        self.databaseVersion = database
        self.bdVersion = bd
    }

    public var errorDescription: String? {
        switch direction {
        case .behind:
            "This database is on schema v\(databaseVersion), and your bd needs v\(bdVersion). It has to be upgraded before it can be read."
        case .ahead:
            "This database is on schema v\(databaseVersion), newer than your bd understands (v\(bdVersion)). Update bd to read it."
        }
    }
}

/// bd declined to upgrade because the database is shared, through a Dolt remote or a shared
/// server, and upgrading this copy alone could split the schema between clones. bd's own guidance
/// is that a person decides; nothing should retry it or force it.
public struct SchemaUpgradeRefused: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
