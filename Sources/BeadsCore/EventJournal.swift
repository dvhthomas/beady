import Foundation

// bd 1.3's events journal: an ordered record of every write made through bd, kept in the same
// transaction as the write, naming who made it. Everything here is pure; BeadsData reads the
// journal and the window decides what to do with what it says.

/// A bd release, as `bd version` reports it.
public struct BeadsVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Finds the first dotted number in text such as `1.3.0`, `v1.4.0-rc.1` or bd's own
    /// `bd version 1.3.0 (f45b249ce: HEAD@…)`. A missing patch number reads as 0.
    public init?(parsing text: String) {
        guard let match = text.firstMatch(of: /(\d+)\.(\d+)(?:\.(\d+))?/),
              let major = Int(match.1), let minor = Int(match.2) else { return nil }
        self.init(major, minor, match.3.flatMap { Int($0) } ?? 0)
    }

    /// The release that added `bd events`.
    public static let eventsJournal = BeadsVersion(1, 3, 0)

    public var supportsEventsJournal: Bool { self >= .eventsJournal }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: BeadsVersion, rhs: BeadsVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// One `bd config` value to write.
public struct ConfigSetting: Equatable, Hashable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// The journal's settings in `.beads/config.yaml`, as bd reports them. A retention floor bd
/// wouldn't give is nil.
public struct JournalSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var retainDays: Int?
    public var retainRows: Int?

    public init(isEnabled: Bool, retainDays: Int?, retainRows: Int?) {
        self.isEnabled = isEnabled
        self.retainDays = retainDays
        self.retainRows = retainRows
    }
}

/// Whether this workspace's bd keeps a journal Beady can follow.
public enum JournalStatus: Equatable, Sendable {
    /// bd is older than 1.3, or wouldn't say which version it is. The file watcher and the
    /// interaction log are all there is.
    case unsupported(BeadsVersion?)
    /// bd can keep a journal; the settings say whether this workspace does.
    case supported(BeadsVersion, JournalSettings)

    public var isOn: Bool {
        if case .supported(_, let settings) = self { return settings.isEnabled }
        return false
    }

    public var canBeTurnedOn: Bool {
        if case .supported(_, let settings) = self { return !settings.isEnabled }
        return false
    }
}

/// How much journal to keep. bd keeps a week, or the newest 100,000 records, whichever is more.
/// Beady reads it for one thing: who touched a bead in the last few minutes, while the window is
/// open. A day covers any working session with room to spare, and a thousand records keep the
/// latest work visible after a quiet weekend, so every record bd writes on Beady's behalf is
/// gone within a day rather than a week.
public enum JournalRetention {
    public static let bdDefaultDays = 7
    public static let bdDefaultRows = 100_000
    public static let days = 1
    public static let rows = 1_000

    /// What turning the journal on writes. Retention is lowered only where bd's own default
    /// still stands: a floor someone chose, larger or smaller, is theirs, and one bd wouldn't
    /// report is left alone rather than guessed at.
    public static func settings(toEnable current: JournalSettings) -> [ConfigSetting] {
        var settings = [ConfigSetting(key: "events-journal", value: "true")]
        if current.retainDays == bdDefaultDays {
            settings.append(ConfigSetting(key: "events-journal-retain-days", value: String(days)))
        }
        if current.retainRows == bdDefaultRows {
            settings.append(ConfigSetting(key: "events-journal-retain-rows", value: String(rows)))
        }
        return settings
    }
}

/// One journal record: a write that committed, in commit order.
public struct JournalRecord: Equatable, Sendable {
    /// Gapless and strictly increasing within one clone; the checkpoint to resume from.
    public let seq: Int64
    public let date: Date
    /// create, update, close, delete, dep_add, dep_remove or comment.
    public let op: String
    public let issueID: IssueID
    /// Nil for bd's own follow-on writes, such as a bead's blocked state recomputed after
    /// another closed; nobody made those.
    public let actor: String?

    public init(seq: Int64, date: Date, op: String, issueID: IssueID, actor: String?) {
        self.seq = seq
        self.date = date
        self.op = op
        self.issueID = issueID
        self.actor = actor
    }
}

/// What one read of the journal found.
public enum JournalRead: Equatable, Sendable {
    case records([JournalRecord])
    /// The checkpoint fell below what bd still keeps; `floor` is the oldest record left.
    case truncated(floor: Int64)
}

/// Where Beady has got to in the journal, and what it has seen there lately.
public struct JournalFeed: Equatable, Sendable {
    /// The highest `seq` read; the next read asks for records after it.
    public private(set) var checkpoint: Int64 = 0
    /// Newest first.
    private var entries: [ActivityEntry] = []

    public init() {}

    public var activity: ActivityLog { ActivityLog(entries: entries) }

    /// Folds one read in. Records at or below the checkpoint were seen already, so reading the
    /// same span twice changes nothing; activity from before `cutoff` is let go. A pruned
    /// checkpoint moves up to just below bd's floor, accepting the gap: the window reloads the
    /// whole database on a change anyway, so only a little attribution is lost.
    public func applying(_ read: JournalRead, keepingSince cutoff: Date) -> JournalFeed {
        var next = self
        switch read {
        case .truncated(let floor):
            next.checkpoint = max(checkpoint, floor - 1)
        case .records(let records):
            let fresh = records.filter { $0.seq > checkpoint }
            next.checkpoint = fresh.map(\.seq).max() ?? checkpoint
            let added = fresh.compactMap(Self.entry).reversed()
            next.entries = (Array(added) + entries).filter { $0.date >= cutoff }
        }
        return next
    }

    /// A record as activity, or nil for one nobody made.
    private static func entry(_ record: JournalRecord) -> ActivityEntry? {
        guard let actor = record.actor, !actor.isEmpty else { return nil }
        // The journal says what kind of write it was, not which field changed; a create is the
        // one History can match on.
        return ActivityEntry(
            issueID: record.issueID,
            actor: actor,
            date: record.date,
            field: record.op == "create" ? "created" : nil
        )
    }
}
