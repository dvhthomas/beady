import BeadsCore
import Foundation

/// What was found at the folder the user chose to open, as facts the app layer gathers.
public struct ChosenFolder: Equatable, Sendable {
    /// The project folder: the chosen one, or the parent when `.beads` itself was chosen.
    public var path: String
    /// `.beads` exists and bd has initialised it.
    public var hasBeadsDatabase: Bool
    /// `.git` is inside the folder: a directory, or a worktree's file.
    public var isGitRepository: Bool
    /// The database itself is in `.beads`, not only bd's configuration. A fresh clone of a
    /// repository that uses beads has the configuration (it is tracked in git) and no database.
    public var hasDatabaseFiles: Bool

    public init(path: String, hasBeadsDatabase: Bool, isGitRepository: Bool, hasDatabaseFiles: Bool? = nil) {
        self.path = path
        self.hasBeadsDatabase = hasBeadsDatabase
        self.isGitRepository = isGitRepository
        self.hasDatabaseFiles = hasDatabaseFiles ?? hasBeadsDatabase
    }
}

/// What opening a chosen folder does.
public enum OpenDecision: Equatable, Sendable {
    /// It holds a database already.
    case open
    /// bd's configuration is there and no database is in the folder. Whether that is a fresh
    /// clone, a database kept elsewhere (a server, another folder) or something to restore is
    /// bd's to say: ask it for its bootstrap plan, then `decide(_:for:)`.
    case askBootstrapPlan
    /// It holds a git repository and no database: ask before making one.
    case offerNewDatabase(NewDatabasePlan)
    /// Neither; the reason is for the user.
    case refuse(String)
}

public enum WorkspaceOpening {
    /// The one decision. A database is opened wherever it is; one is offered only inside a git
    /// repository. `bd init` in a plain folder would run `git init` there itself, which is more
    /// than opening a folder should do, so that case is a refusal with the reason.
    public static func decide(_ folder: ChosenFolder) -> OpenDecision {
        if folder.hasBeadsDatabase { return folder.hasDatabaseFiles ? .open : .askBootstrapPlan }
        if folder.isGitRepository { return .offerNewDatabase(NewDatabasePlan(projectPath: folder.path)) }
        return .refuse(String(
            localized: "\(folder.path) has no .beads database, and it isn't a git repository (no .git inside it), so Beady won't create one there. Run git init in it first, or choose a repository.",
            bundle: .module, comment: "The folder's path"
        ))
    }
}

/// What to do once bd has said what `bd bootstrap` would do in a folder.
public enum BootstrapDecision: Equatable, Sendable {
    case open
    case offer(BootstrapOffer)
}

public extension WorkspaceOpening {
    /// bd's plan decides. Nothing to do, or no answer from bd, opens the folder as before: a
    /// database on a server or behind a redirect is no reason to offer anything.
    static func decide(_ plan: BootstrapPlan?, for path: String) -> BootstrapDecision {
        guard let plan, !plan.isNothingToDo else { return .open }
        return .offer(BootstrapOffer(projectPath: path, plan: plan))
    }
}

/// The offer to run `bd bootstrap` in a folder that has bd's configuration and no database:
/// usually a fresh clone, where it fetches the shared database (plan 0006).
public struct BootstrapOffer: Equatable, Sendable {
    public let projectPath: String
    public let plan: BootstrapPlan

    public init(projectPath: String, plan: BootstrapPlan) {
        self.projectPath = projectPath
        self.plan = plan
    }

    public var folderName: String { URL(fileURLWithPath: projectPath).lastPathComponent }

    public var title: String {
        if plan.clonesFromRemote {
            return String(localized: "Get the beads for \(folderName)?", bundle: .module, comment: "Alert title; the folder's name")
        }
        if plan.createsFreshDatabase {
            return String(localized: "Start an empty beads database in \(folderName)?", bundle: .module, comment: "Alert title; the folder's name")
        }
        return String(localized: "Set up the beads database in \(folderName)?", bundle: .module, comment: "Alert title; the folder's name")
    }

    public var confirmTitle: String {
        if plan.clonesFromRemote { return String(localized: "Get Beads", bundle: .module, comment: "Alert button: fetch the shared database") }
        if plan.createsFreshDatabase { return String(localized: "Start Empty Database", bundle: .module, comment: "Alert button") }
        return String(localized: "Set Up", bundle: .module, comment: "Alert button: run bd bootstrap")
    }

    /// `command` is the exact command line the app will run, from the gateway.
    public func message(command: String) -> String {
        let lead: String
        if plan.clonesFromRemote {
            lead = String(
                localized: "\(folderName) uses beads, and this copy doesn't have the database yet. bd found it on the repository's remote and can fetch it. Nothing here is replaced.",
                bundle: .module, comment: "Alert text; the folder's name"
            )
        } else if plan.createsFreshDatabase {
            lead = String(
                localized: """
                \(folderName) is set up for beads, and bd found no database here, on a remote or in a backup, so it would start an empty one.

                If these beads already exist on another Mac, share them from there first and open this folder again: a database started here would be a separate backlog.
                """,
                bundle: .module, comment: "Alert text; the folder's name"
            )
        } else {
            lead = String(
                localized: "\(folderName) is set up for beads, and this copy doesn't have the database yet.",
                bundle: .module, comment: "Alert text; the folder's name"
            )
        }
        return String(
            localized: """
            \(lead)

            bd says: \(plan.reason)

            bd will run:
            \(command)
            """,
            bundle: .module,
            comment: "Alert text: an explanation, then bd's own reason, then the exact command line"
        )
    }
}

/// The defaults Beady gives a new database. They are deliberately the fewest that make a
/// workspace the app can open:
///
/// - **Prefix**: the folder's name, lowercased, letters and digits with runs of anything else
///   folded to one hyphen, starting with a letter (bd's database name must) and at most 16
///   characters, cut back to a whole word. Diacritics are stripped rather than dropped. A name
///   with nothing usable in it gives `beads`.
/// - **Nothing else**: `--skip-agents` and `--skip-hooks`, so no AGENTS.md, CLAUDE.md, Cursor
///   or Codex files and no git hooks appear in the repository. Those are the owner's call, and
///   `bd setup` and `bd hooks install` add them later. `--non-interactive` because there is no
///   terminal to answer bd's wizards.
/// - **Embedded Dolt**, bd's own default storage; nothing is passed for it.
///
/// bd itself commits `.beads/` and a `.gitignore` entry to the repository as part of init, and
/// touches nothing else there. bd's change journal is a separate decision made when the new
/// workspace opens (`JournalPolicy`).
public struct NewDatabasePlan: Equatable, Sendable {
    public static let maximumPrefixLength = 16
    public static let fallbackPrefix = "beads"

    public let projectPath: String
    public let prefix: String

    public init(projectPath: String, prefix: String) {
        self.projectPath = projectPath
        self.prefix = prefix
    }

    public init(projectPath: String) {
        self.init(projectPath: projectPath, prefix: Self.prefix(forFolderNamed: URL(fileURLWithPath: projectPath).lastPathComponent))
    }

    public var folderName: String { URL(fileURLWithPath: projectPath).lastPathComponent }

    public static func prefix(forFolderNamed name: String) -> String {
        let plain = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var words: [String] = []
        var word = ""
        for scalar in plain.unicodeScalars {
            if scalar.isASCII, (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)) {
                word.unicodeScalars.append(scalar)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        // Database names start with a letter or underscore; drop what comes before one.
        while let first = words.first?.unicodeScalars.first, !first.properties.isAlphabetic {
            words[0].unicodeScalars.removeFirst()
            if words[0].isEmpty { words.removeFirst() }
        }
        guard !words.isEmpty else { return fallbackPrefix }

        var prefix = words[0]
        for next in words.dropFirst() {
            guard prefix.count + 1 + next.count <= maximumPrefixLength else { break }
            prefix += "-" + next
        }
        return String(prefix.prefix(maximumPrefixLength))
    }

    public var offerTitle: String {
        String(localized: "Create a beads database in \(folderName)?", bundle: .module, comment: "Alert title; the folder's name")
    }

    /// `command` is the exact command line the app will run, from the gateway.
    public func offerMessage(command: String) -> String {
        String(
            localized: """
            \(folderName) is a git repository without a .beads database. Beady can make one: \
            bd's embedded Dolt storage, beads named \(prefix)-<id>, no agent files and no git hooks.

            bd will run:
            \(command)

            bd commits the new .beads folder and a .gitignore entry to the repository, and \
            touches nothing else.
            """,
            bundle: .module,
            comment: "Alert text; the folder's name, the issue-id prefix, then the exact command line"
        )
    }
}
