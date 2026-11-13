import Foundation

// Sharing: where a beads database lives besides this Mac, and whether that is current.
// Everything here is what bd reports, as values; plan 0006 records where each comes from.

/// A Dolt remote, as `bd dolt remote list` names it.
public struct DoltRemote: Equatable, Sendable {
    public let name: String
    /// bd's own form, e.g. `git+https://github.com/org/repo.git`.
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    /// True when the data travels through a git repository, under `refs/dolt/data`.
    public var isGitHosted: Bool { url.hasPrefix("git+") }

    /// The URL without Dolt's transport prefix and without any credentials, for showing.
    public var displayURL: String {
        var text = url.hasPrefix("git+") ? String(url.dropFirst(4)) : url
        if text.hasPrefix("file://") { return String(text.dropFirst(7)) }
        // `scheme://user:secret@host/…`: keep the host, drop what precedes the @.
        if let scheme = text.range(of: "://"),
           let slash = text[scheme.upperBound...].firstIndex(of: "/") ?? Optional(text.endIndex),
           let at = text[scheme.upperBound..<slash].lastIndex(of: "@") {
            text.removeSubrange(scheme.upperBound...at)
        }
        return text
    }
}

/// How this database stands against one remote, from `bd federation status`.
public struct PeerStatus: Equatable, Sendable {
    public let name: String
    public let isReachable: Bool
    /// bd's message when the remote couldn't be reached.
    public let reachError: String?
    /// Commits here that the remote lacks; nil when bd couldn't say.
    public let ahead: Int?
    /// Commits on the remote that aren't here; nil when bd couldn't say.
    public let behind: Int?

    public init(name: String, isReachable: Bool, reachError: String? = nil, ahead: Int?, behind: Int?) {
        self.name = name
        self.isReachable = isReachable
        self.reachError = reachError
        self.ahead = ahead
        self.behind = behind
    }
}

/// How bd stores the database. Embedded is bd's default: in-process, one writer at a time.
public enum StorageMode: Equatable, Sendable {
    case embedded
    /// A Dolt server of some kind; the text is bd's own word for it.
    case other(String)

    public init(doltMode: String?) {
        self = (doltMode ?? "embedded") == "embedded" ? .embedded : .other(doltMode ?? "")
    }
}

/// What one `bd sync` did.
public enum SyncOutcome: Equatable, Sendable {
    /// Pulled, checked and pushed; or there was nothing to do.
    case synced
    case noRemote
    /// `dolt.local-only`: bd won't contact a remote.
    case localOnly
    /// A merge bd won't settle by itself. Nothing was pushed and nothing here was lost.
    case conflict(tables: [String])
    /// Another writer was in the way for every attempt; trying again later is the remedy.
    case busy
    /// Pending edits that block every run; bd's message says what to clear.
    case stuck(String)
    /// This database and the remote's don't share a history: two separately made backlogs.
    case unrelated(String)
    case failed(String)

    /// bd's wording for histories that were never one database.
    public static func isUnrelatedHistory(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("no common ancestor")
    }
}

/// Which side a conflict is settled for. bd's words are `ours` and `theirs`.
public enum ConflictSide: String, Equatable, Sendable {
    case mine = "ours"
    case theirs
}

/// Everything bd reports about sharing, gathered in one read.
public struct SharingFacts: Equatable, Sendable {
    public static let none = SharingFacts(remotes: [], peers: [], isLocalOnly: false, storage: .embedded)

    public let remotes: [DoltRemote]
    public let peers: [PeerStatus]
    public let isLocalOnly: Bool
    public let storage: StorageMode

    public init(remotes: [DoltRemote], peers: [PeerStatus], isLocalOnly: Bool, storage: StorageMode) {
        self.remotes = remotes
        self.peers = peers
        self.isLocalOnly = isLocalOnly
        self.storage = storage
    }

    /// The remote `bd sync` and `bd dolt push` use when none is named: `origin`, or the only one.
    public var remote: DoltRemote? {
        remotes.first { $0.name == "origin" } ?? remotes.first
    }
}

/// Where the beads live and whether that is current: the one thing the app says about sharing.
public enum SharingState: Equatable, Sendable {
    /// bd is configured to keep this database off the network.
    case keptLocal
    /// No remote: the beads are on this Mac and nowhere else.
    case notShared
    /// A remote is set up and nothing has been published to it.
    case neverPublished(DoltRemote)
    case unreachable(DoltRemote, reason: String?)
    /// The remote is set up but bd didn't report how this database stands against it.
    case unknown(DoltRemote)
    case pending(DoltRemote, toSend: Int, toReceive: Int)
    case inSync(DoltRemote)
    /// The last sync stopped on a conflict. `canChooseSide` is true where bd can settle it for
    /// one side in a single pull, which is embedded storage.
    case conflict(DoltRemote, canChooseSide: Bool)
    /// The last sync found a remote that holds a different backlog.
    case unrelated(DoltRemote)

    /// `lastSync` is the outcome of the last sync this session, if any: a halted merge leaves
    /// nothing behind for bd to report, so the outcome is the only record of it.
    public static func derive(_ facts: SharingFacts, lastSync: SyncOutcome? = nil) -> SharingState {
        if facts.isLocalOnly { return .keptLocal }
        guard let remote = facts.remote else { return .notShared }
        switch lastSync {
        case .conflict: return .conflict(remote, canChooseSide: facts.storage == .embedded)
        case .unrelated: return .unrelated(remote)
        default: break
        }
        guard let peer = facts.peers.first(where: { $0.name == remote.name }) else { return .unknown(remote) }
        guard peer.isReachable else { return .unreachable(remote, reason: peer.reachError) }
        guard let ahead = peer.ahead, let behind = peer.behind else { return .neverPublished(remote) }
        return ahead == 0 && behind == 0 ? .inSync(remote) : .pending(remote, toSend: ahead, toReceive: behind)
    }

    public var remote: DoltRemote? {
        switch self {
        case .keptLocal, .notShared: nil
        case .neverPublished(let remote), .unreachable(let remote, _), .unknown(let remote),
             .pending(let remote, _, _), .inSync(let remote), .conflict(let remote, _), .unrelated(let remote): remote
        }
    }

    /// True when something is wrong that a person has to look at.
    public var needsAttention: Bool {
        switch self {
        case .unreachable, .conflict, .unrelated: true
        case .keptLocal, .notShared, .neverPublished, .unknown, .pending, .inSync: false
        }
    }
}

/// What `bd bootstrap` would do in a folder, from its dry run.
public struct BootstrapPlan: Equatable, Sendable {
    /// bd's own word: `none`, `sync` (clone from the remote), `init` (a fresh database), or
    /// another recovery it knows, such as a restore from backup.
    public let action: String
    /// A database is already there; bootstrap would leave it alone.
    public let hasExistingDatabase: Bool
    /// bd's sentence about why.
    public let reason: String

    public init(action: String, hasExistingDatabase: Bool, reason: String) {
        self.action = action
        self.hasExistingDatabase = hasExistingDatabase
        self.reason = reason
    }

    /// Nothing for bootstrap to do: open the folder as it is.
    public var isNothingToDo: Bool { hasExistingDatabase || action == "none" }
    /// The database is on the remote and would be cloned from it.
    public var clonesFromRemote: Bool { !isNothingToDo && action == "sync" }
    /// An empty database would be made here, sharing nothing with anyone else's.
    public var createsFreshDatabase: Bool { !isNothingToDo && action == "init" }
}

/// One checkout of the repository, from `bd worktree list`.
public struct Checkout: Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String
    public let branch: String
    public let isMain: Bool

    public init(name: String, path: String, branch: String, isMain: Bool) {
        self.name = name
        self.path = path
        self.branch = branch
        self.isMain = isMain
    }

    public var id: String { path }
}

/// One of bd's git hooks, from `bd hooks list`.
public struct GitHook: Equatable, Sendable {
    public let name: String
    public let isInstalled: Bool
    public let isOutdated: Bool

    public init(name: String, isInstalled: Bool, isOutdated: Bool = false) {
        self.name = name
        self.isInstalled = isInstalled
        self.isOutdated = isOutdated
    }
}

/// What `bd context` says about the workspace bd actually resolved.
public struct WorkspaceContext: Equatable, Sendable {
    public let bdVersion: String?
    public let storage: StorageMode
    /// `maintainer` or `contributor`.
    public let role: String?
    /// The folder bd was asked about is a linked worktree of `repoRoot`.
    public let isWorktree: Bool
    public let repoRoot: String?
    /// Where the `.beads` in use is; in a worktree, the main checkout's.
    public let beadsDirectory: String?
    /// The `.beads` in use was reached through a redirect or `BEADS_DIR`.
    public let isRedirected: Bool

    public init(
        bdVersion: String?, storage: StorageMode, role: String?, isWorktree: Bool,
        repoRoot: String?, beadsDirectory: String?, isRedirected: Bool
    ) {
        self.bdVersion = bdVersion
        self.storage = storage
        self.role = role
        self.isWorktree = isWorktree
        self.repoRoot = repoRoot
        self.beadsDirectory = beadsDirectory
        self.isRedirected = isRedirected
    }
}

/// The facts the Workspace Setup sheet lists besides sharing and backup. Each part is nil or
/// empty when bd wouldn't say, and the sheet leaves that row out rather than guess.
public struct WorkspaceSetup: Equatable, Sendable {
    public static let unknown = WorkspaceSetup(context: nil, checkouts: [], hooks: [], exportsIssuesFile: nil)

    public let context: WorkspaceContext?
    public let checkouts: [Checkout]
    public let hooks: [GitHook]
    /// `export.auto`: bd keeps `.beads/issues.jsonl` current, and its pre-commit hook, when
    /// installed, adds the file to each commit.
    public let exportsIssuesFile: Bool?

    public init(context: WorkspaceContext?, checkouts: [Checkout], hooks: [GitHook], exportsIssuesFile: Bool?) {
        self.context = context
        self.checkouts = checkouts
        self.hooks = hooks
        self.exportsIssuesFile = exportsIssuesFile
    }

    public var installedHooks: [GitHook] { hooks.filter(\.isInstalled) }
}
