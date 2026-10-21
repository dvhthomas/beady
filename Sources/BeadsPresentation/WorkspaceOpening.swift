import Foundation

/// What was found at the folder the user chose to open, as facts the app layer gathers.
public struct ChosenFolder: Equatable, Sendable {
    /// The project folder: the chosen one, or the parent when `.beads` itself was chosen.
    public var path: String
    /// `.beads` exists and bd has initialised it.
    public var hasBeadsDatabase: Bool
    /// `.git` is inside the folder: a directory, or a worktree's file.
    public var isGitRepository: Bool

    public init(path: String, hasBeadsDatabase: Bool, isGitRepository: Bool) {
        self.path = path
        self.hasBeadsDatabase = hasBeadsDatabase
        self.isGitRepository = isGitRepository
    }
}

/// What opening a chosen folder does.
public enum OpenDecision: Equatable, Sendable {
    /// It holds a database already.
    case open
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
        if folder.hasBeadsDatabase { return .open }
        if folder.isGitRepository { return .offerNewDatabase(NewDatabasePlan(projectPath: folder.path)) }
        return .refuse(
            "\(folder.path) has no .beads database, and it isn't a git repository (no .git inside it), " +
            "so Beady won't create one there. Run git init in it first, or choose a repository."
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

    public var offerTitle: String { "Create a beads database in \(folderName)?" }

    /// `command` is the exact command line the app will run, from the gateway.
    public func offerMessage(command: String) -> String {
        """
        \(folderName) is a git repository without a .beads database. Beady can make one: \
        bd's embedded Dolt storage, beads named \(prefix)-<id>, no agent files and no git hooks.

        bd will run:
        \(command)

        bd commits the new .beads folder and a .gitignore entry to the repository, and \
        touches nothing else.
        """
    }
}
