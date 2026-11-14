import BeadsCore
import Foundation

// The words and choices for sharing (plan 0006). Pure: each takes what bd reported and returns
// what the views show, so every sentence a person reads about sharing is tested here.

/// What can be done about a sharing state, at most two at a time.
public enum SharingAction: Equatable, Sendable {
    /// Open the Share Beads sheet.
    case share
    case sync
    /// Ask bd again how the database stands against its remote.
    case checkAgain
    case settleConflict(keeping: ConflictSide)

    public var title: String {
        switch self {
        case .share: String(localized: "Share Beads…", bundle: .module, comment: "Button and command: open the Share Beads sheet")
        case .sync: String(localized: "Sync Now", bundle: .module, comment: "Button and command: run bd sync")
        case .checkAgain: String(localized: "Check Again", bundle: .module, comment: "Button: ask bd about the remote again")
        case .settleConflict(.mine): String(localized: "Keep This Mac's", bundle: .module, comment: "Button: settle a conflict for the local side")
        case .settleConflict(.theirs): String(localized: "Take the Remote's", bundle: .module, comment: "Button: settle a conflict for the remote side")
        }
    }
}

/// The one thing the toolbar says about sharing, and the sentence behind it.
public struct SharingSummary: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        /// Nothing to act on.
        case quiet
        case good
        /// Something is waiting: beads to send or receive.
        case waiting
        /// A person has to look at this.
        case problem
    }

    /// A few words, for the toolbar.
    public let word: String
    /// An SF Symbol name.
    public let symbol: String
    public let tone: Tone
    /// A sentence or two, for the popover and the setup sheet.
    public let detail: String
    /// What can be started now: none while bd is working.
    public let actions: [SharingAction]
    /// bd is running a sync or a share: the symbol turns, and the buttons wait.
    public let isWorking: Bool
    /// The buttons to lay out, working or not. They stay where they are while bd works, drawn
    /// disabled, so the popover doesn't change size under the pointer: a popover that shrank for
    /// the length of a real sync came back clipped.
    public let buttons: [SharingAction]

    public init(word: String, symbol: String, tone: Tone, detail: String, actions: [SharingAction], isWorking: Bool = false, buttons: [SharingAction]? = nil) {
        self.word = word
        self.symbol = symbol
        self.tone = tone
        self.detail = detail
        self.actions = actions
        self.isWorking = isWorking
        self.buttons = buttons ?? actions
    }
}

public extension SharingState {
    /// `isWorking` is true while a sync or a share is running.
    func summary(isWorking: Bool = false) -> SharingSummary {
        let summary = settledSummary
        guard isWorking else { return summary }
        return SharingSummary(
            word: String(localized: "Syncing…", bundle: .module, comment: "Toolbar sharing status while bd sync runs"),
            symbol: "arrow.triangle.2.circlepath", tone: .quiet, detail: summary.detail, actions: [],
            isWorking: true, buttons: summary.actions
        )
    }

    private var settledSummary: SharingSummary {
        switch self {
        case .keptLocal:
            return SharingSummary(
                word: String(localized: "Kept on this Mac", bundle: .module, comment: "Toolbar sharing status: bd is set to local-only"),
                symbol: "laptopcomputer", tone: .quiet,
                detail: String(localized: "bd is set to keep this database off the network (dolt.local-only), so there is nothing to share or sync.", bundle: .module),
                actions: []
            )
        case .notShared:
            return SharingSummary(
                word: String(localized: "Only on this Mac", bundle: .module, comment: "Toolbar sharing status: no remote"),
                symbol: "laptopcomputer", tone: .quiet,
                detail: String(localized: "These beads are in this Mac's copy of the repository and nowhere else. Another Mac, or a teammate, can't see them.", bundle: .module),
                actions: [.share]
            )
        case .neverPublished(let remote):
            return SharingSummary(
                word: String(localized: "Not sent yet", bundle: .module, comment: "Toolbar sharing status: a remote is set up and nothing was pushed"),
                symbol: "icloud.and.arrow.up", tone: .waiting,
                detail: String(localized: "\(remote.name) is set up as the place to share these beads, and nothing has been sent to it yet.", bundle: .module, comment: "The remote's name"),
                actions: [.share]
            )
        case .unreachable(let remote, let reason):
            let lead = String(localized: "bd couldn't reach \(remote.name). Until it can, changes stay on this Mac and nothing new arrives.", bundle: .module, comment: "The remote's name")
            return SharingSummary(
                word: String(localized: "Can't reach \(remote.name)", bundle: .module, comment: "Toolbar sharing status; the remote's name"),
                symbol: "icloud.slash", tone: .problem,
                detail: reason.map { "\(lead)\n\n\($0)" } ?? lead,
                actions: [.checkAgain]
            )
        case .unknown(let remote):
            return SharingSummary(
                word: String(localized: "Shared with \(remote.name)", bundle: .module, comment: "Toolbar sharing status; the remote's name"),
                symbol: "icloud", tone: .quiet,
                detail: String(localized: "bd didn't say how this database stands against \(remote.name). A sync will find out.", bundle: .module, comment: "The remote's name"),
                actions: [.sync, .checkAgain]
            )
        case .pending(let remote, let toSend, let toReceive):
            let word: String
            if toSend > 0, toReceive > 0 {
                word = String(localized: "\(toSend) to send · \(toReceive) to receive", bundle: .module, comment: "Toolbar sharing status: counts of changes each way")
            } else if toSend > 0 {
                word = String(localized: "\(toSend) to send", bundle: .module, comment: "Toolbar sharing status: count of local changes")
            } else {
                word = String(localized: "\(toReceive) to receive", bundle: .module, comment: "Toolbar sharing status: count of remote changes")
            }
            // A sentence each way, so each can take its own plural.
            var sentences: [String] = []
            if toSend > 0 {
                sentences.append(String(localized: "\(toSend) changes here aren't on \(remote.name) yet.", bundle: .module, comment: "Plural on the count of changes; then the remote's name"))
            }
            if toReceive > 0 {
                sentences.append(String(localized: "\(toReceive) changes on \(remote.name) aren't here yet.", bundle: .module, comment: "Plural on the count of changes; then the remote's name"))
            }
            let detail = sentences.joined(separator: " ")
            return SharingSummary(word: word, symbol: "arrow.triangle.2.circlepath.icloud", tone: .waiting, detail: detail, actions: [.sync])
        case .inSync(let remote):
            return SharingSummary(
                word: String(localized: "In sync", bundle: .module, comment: "Toolbar sharing status"),
                symbol: "checkmark.icloud", tone: .good,
                detail: String(localized: "Everything here is on \(remote.name), and everything on \(remote.name) is here, as of the last check.", bundle: .module, comment: "The remote's name, twice"),
                actions: [.sync]
            )
        case .conflict(let remote, let canChooseSide):
            let lead = String(localized: "A change here and a change on \(remote.name) can't both be kept, for example a bead deleted on one side and edited on the other. bd stopped before changing anything: nothing was sent and nothing here was lost.", bundle: .module, comment: "The remote's name")
            let choice = canChooseSide
                ? String(localized: "bd doesn't say which beads. Choosing a side applies to every bead in conflict; everything else merges as usual.", bundle: .module)
                : String(localized: "On this kind of storage bd leaves the conflict to be settled with bd conflicts, in a terminal.", bundle: .module)
            return SharingSummary(
                word: String(localized: "Needs a decision", bundle: .module, comment: "Toolbar sharing status: a merge conflict"),
                symbol: "exclamationmark.icloud", tone: .problem,
                detail: "\(lead)\n\n\(choice)",
                actions: canChooseSide ? [.settleConflict(keeping: .mine), .settleConflict(keeping: .theirs)] : []
            )
        case .unrelated(let remote):
            return SharingSummary(
                word: String(localized: "Two different backlogs", bundle: .module, comment: "Toolbar sharing status: unrelated histories"),
                symbol: "exclamationmark.icloud", tone: .problem,
                detail: String(localized: "The beads here and the beads on \(remote.name) were started separately, so bd can't merge them. Bringing them together means choosing one and moving the other's beads into it by hand; bd's guidance is to keep the one on \(remote.name) and run bd bootstrap in a fresh clone. Beady won't pick for you.", bundle: .module, comment: "The remote's name, twice"),
                actions: []
            )
        }
    }
}

public extension SyncOutcome {
    /// What to tell the person who pressed Sync Now, when the state alone doesn't say it.
    /// Nil when the status word already tells the story.
    var notice: String? {
        switch self {
        case .synced, .conflict, .unrelated, .noRemote, .localOnly:
            nil
        case .busy:
            String(localized: "Another bd session was writing the whole time, so nothing was sent. Nothing is wrong; sync again in a moment.", bundle: .module)
        case .stuck(let message):
            String(localized: "bd found edits it can't publish and can't clear by itself, so nothing was sent. bd says: \(message)", bundle: .module, comment: "bd's message")
        case .failed(let message):
            String(localized: "The sync didn't go through. bd says: \(message)", bundle: .module, comment: "bd's message")
        }
    }
}

/// Who a database is for, the one question the Share Beads sheet asks.
public enum ShareAudience: String, CaseIterable, Identifiable, Sendable {
    case onlyMe
    case severalMacs
    case team

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onlyMe: String(localized: "Only me, on this Mac", bundle: .module, comment: "Share Beads: audience")
        case .severalMacs: String(localized: "Me, on several Macs", bundle: .module, comment: "Share Beads: audience")
        case .team: String(localized: "A team", bundle: .module, comment: "Share Beads: audience")
        }
    }

    public var symbol: String {
        switch self {
        case .onlyMe: "laptopcomputer"
        case .severalMacs: "macbook.and.iphone"
        case .team: "person.2"
        }
    }

    public var blurb: String {
        switch self {
        case .onlyMe: String(localized: "Nothing leaves this Mac. A backup keeps a second copy on a disk you choose.", bundle: .module, comment: "Share Beads: audience description")
        case .severalMacs: String(localized: "The beads follow the repository to each Mac you clone it on.", bundle: .module, comment: "Share Beads: audience description")
        case .team: String(localized: "Everyone who can read the repository shares one backlog.", bundle: .module, comment: "Share Beads: audience description")
        }
    }

    public var shares: Bool { self != .onlyMe }
}

/// What pressing Share Beads will do: the bd commands, and what follows from them. Built from
/// what bd reported and the URL in the sheet's field; nothing is assumed about the remote
/// beyond what the URL says.
public struct SharePlan: Equatable, Sendable {
    /// bd's default remote name, and the one its docs use throughout.
    public static let remoteName = "origin"

    public let steps: [SharingStep]
    /// Where the beads will be readable, as shown.
    public let destination: String
    /// Things that will be true afterwards that the person might not expect.
    public let consequences: [String]
    /// Why the plan can't run, when it can't.
    public let problem: String?

    public var canShare: Bool { problem == nil && !steps.isEmpty }

    /// - Parameters:
    ///   - facts: what bd reported; a remote that is already there is used as it is.
    ///   - gitOrigin: the repository's git origin, as git reports it.
    ///   - url: the sheet's field: the origin by default, or any Dolt remote URL.
    public static func make(facts: SharingFacts, gitOrigin: String?, url: String, audience: ShareAudience) -> SharePlan {
        guard audience.shares else {
            return SharePlan(steps: [], destination: "", consequences: [], problem: nil)
        }
        if facts.isLocalOnly {
            return SharePlan(steps: [], destination: "", consequences: [], problem: String(
                localized: "bd is set to keep this database off the network (dolt.local-only in .beads/config.yaml). Sharing starts with turning that off, which is a decision for whoever set it.", bundle: .module
            ))
        }
        let existing = facts.remote
        let typed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing == nil, typed.isEmpty {
            return SharePlan(steps: [], destination: "", consequences: [], problem: String(
                localized: "Enter where to share the beads: the repository's git URL, or any Dolt remote.", bundle: .module
            ))
        }
        if existing == nil, typed.hasPrefix("-") {
            // bd refuses these too; saying so here is quicker than running it to find out.
            return SharePlan(steps: [], destination: typed, consequences: [], problem: String(
                localized: "A remote URL can't begin with a hyphen.", bundle: .module
            ))
        }

        let isGitOrigin = existing == nil && typed == gitOrigin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ridesInGit = existing?.isGitHosted ?? (isGitOrigin || Self.looksLikeGit(typed))
        let destination = existing?.displayURL ?? DoltRemote(name: remoteName, url: typed).displayURL
        var steps: [SharingStep] = []
        if existing == nil {
            steps.append(.addRemote(name: remoteName, url: typed, allowGitOrigin: isGitOrigin))
        }
        steps.append(.publish)

        var consequences = [String(
            localized: "Anyone who can read \(destination) will be able to read every bead here, with its history.",
            bundle: .module, comment: "Share Beads: who can read; the value is the remote's URL"
        )]
        if ridesInGit {
            consequences.append(String(
                localized: "bd keeps the beads in that repository under refs/dolt/data, outside every branch, and adds one small branch named __dolt_remote_info__. Commits, branches and pull requests are untouched.",
                bundle: .module, comment: "Share Beads: what appears on a git remote"
            ))
        }
        if existing == nil {
            consequences.append(String(
                localized: "bd records the remote as sync.remote in .beads/config.yaml. Commit that file with git, so other clones find the beads.",
                bundle: .module, comment: "Share Beads: the tracked file bd changes"
            ))
        }
        consequences.append(audience == .team
            ? String(localized: "A teammate gets the beads by opening their clone in Beady, or by running bd bootstrap in it. Everyone should be on the same bd version; bd refuses to mix them.", bundle: .module, comment: "Share Beads: how others join")
            : String(localized: "On another Mac, clone the repository and open it in Beady, or run bd bootstrap in it.", bundle: .module, comment: "Share Beads: how another Mac joins"))
        consequences.append(String(
            localized: "Beady sends and receives when you press Sync Now, never by itself. Agents do the same with bd sync.",
            bundle: .module, comment: "Share Beads: no automatic sync"
        ))
        return SharePlan(steps: steps, destination: destination, consequences: consequences, problem: nil)
    }

    /// A URL that will be carried by git rather than by a Dolt service: the forms bd rewrites
    /// to `git+…`, and those already written that way.
    static func looksLikeGit(_ url: String) -> Bool {
        if url.hasPrefix("git+") || url.hasPrefix("git@") || url.hasPrefix("ssh://") { return true }
        if url.contains("doltremoteapi") || url.hasPrefix("dolthub://") { return false }
        return url.hasSuffix(".git")
    }
}

/// One row of the Workspace Setup sheet: a fact about this workspace, and at most one thing to
/// do about it.
public struct SetupRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case database, checkouts, sharing, backup, commits, bd
    }

    public enum Level: Equatable, Sendable {
        case good
        case info
        case attention
    }

    public enum Action: Equatable, Sendable {
        case sharing(SharingAction)
        case setUpBackup
        case backUpNow

        public var title: String {
            switch self {
            case .sharing(let action): action.title
            case .setUpBackup: String(localized: "Choose Folder…", bundle: .module, comment: "Workspace Setup button: pick a backup folder")
            case .backUpNow: String(localized: "Back Up Now", bundle: .module, comment: "Workspace Setup button")
            }
        }
    }

    public let kind: Kind
    public let level: Level
    public let title: String
    public let detail: String
    public let action: Action?

    public var id: String { kind.rawValue }
}

public enum WorkspaceSetupRows {
    /// Up to this many checkouts are listed by branch; beyond it only their number is given.
    public static let namedCheckoutLimit = 4

    /// The tallest the sheet's facts may stand before they scroll under a title and buttons
    /// that don't. Tall enough for every row on an ordinary screen; on a small one it leaves
    /// the room the title, the buttons and the window's own toolbar take, so Done is never
    /// below the screen's edge. `nil` when the screen can't be asked.
    public static func factsMaxHeight(visibleScreenHeight: Double?) -> Double {
        guard let visibleScreenHeight else { return 420 }
        return min(520, max(200, visibleScreenHeight - 280))
    }

    /// The rows, in reading order. A row whose facts bd wouldn't give is left out.
    /// - Parameters:
    ///   - sharing: nil when bd couldn't be asked.
    ///   - backupSummary: the model's own phrase, e.g. "backed up 6 minutes ago".
    public static func rows(
        sharing: SharingState?,
        isSyncing: Bool = false,
        backup: BackupStatus,
        backupSummary: String,
        setup: WorkspaceSetup,
        beadCount: Int
    ) -> [SetupRow] {
        var rows: [SetupRow] = []

        // Database
        // A sentence for the count, so it can take its own plural, then one for the place.
        let count = String(localized: "\(beadCount) beads.", bundle: .module, comment: "Plural on the count of beads")
        let place: String? = setup.context.flatMap { context in
            context.beadsDirectory.map { directory in
                context.isRedirected
                    ? String(localized: "Kept outside this checkout, in \(directory).", bundle: .module, comment: "A folder path")
                    : String(localized: "Kept in \(directory).", bundle: .module, comment: "A folder path")
            }
        }
        let storage: String? = setup.context.map { context in
            switch context.storage {
            case .embedded:
                String(localized: "bd's embedded storage: no server, one writer at a time.", bundle: .module)
            case .other(let mode):
                String(localized: "Stored through a Dolt server (\(mode)).", bundle: .module, comment: "bd's word for the storage mode")
            }
        }
        rows.append(SetupRow(
            kind: .database, level: .good,
            title: String(localized: "Database", bundle: .module, comment: "Workspace Setup row"),
            detail: [count, place, storage].compactMap { $0 }.joined(separator: " "), action: nil
        ))

        // Checkouts: only worth a row when there is more than one. A few are named, because
        // their branches are recognisable; a repository worked by agents can have ninety, and
        // then the count is the fact.
        if setup.checkouts.count > 1 {
            let detail: String
            if setup.checkouts.count <= namedCheckoutLimit {
                let names = setup.checkouts.map { $0.branch.isEmpty ? $0.name : $0.branch }.joined(separator: ", ")
                detail = String(localized: "\(setup.checkouts.count) checkouts of this repository use the one database, so a bead changed in one is changed in all: \(names).", bundle: .module, comment: "Count of checkouts, then their branch names")
            } else {
                detail = String(localized: "\(setup.checkouts.count) checkouts of this repository use the one database, so a bead changed in one is changed in all.", bundle: .module, comment: "Count of checkouts, when there are too many to name")
            }
            rows.append(SetupRow(
                kind: .checkouts, level: .info,
                title: String(localized: "Checkouts on this Mac", bundle: .module, comment: "Workspace Setup row"),
                detail: detail, action: nil
            ))
        }

        // Sharing
        if let sharing {
            let summary = sharing.summary(isWorking: isSyncing)
            rows.append(SetupRow(
                kind: .sharing,
                level: summary.tone == .problem ? .attention : (summary.tone == .good ? .good : .info),
                title: String(localized: "Sharing", bundle: .module, comment: "Workspace Setup row"),
                detail: "\(summary.word). \(summary.detail)",
                action: summary.actions.first.map { .sharing($0) }
            ))
        }

        // Backup
        let isOffThisMac: Bool = switch sharing {
        case .inSync, .pending: true
        default: false
        }
        let backupDetail: String
        if let destination = backup.destination {
            backupDetail = String(localized: "\(backupSummary.capitalizedFirst), to \(destination).", bundle: .module, comment: "The backup status phrase, then the folder")
        } else if isOffThisMac {
            backupDetail = String(localized: "Not set up. Sharing already keeps a copy off this Mac.", bundle: .module)
        } else {
            backupDetail = String(localized: "Not set up. If this Mac's disk fails, the beads go with it.", bundle: .module)
        }
        rows.append(SetupRow(
            kind: .backup,
            level: backup.isConfigured ? .good : (isOffThisMac ? .info : .attention),
            title: String(localized: "Backup", bundle: .module, comment: "Workspace Setup row"),
            detail: backupDetail,
            action: backup.isConfigured ? .backUpNow : .setUpBackup
        ))

        // Commits: bd's git hooks are how beads get into commits, and they are optional.
        if !setup.hooks.isEmpty {
            let installed = setup.installedHooks
            let names = installed.map(\.name).joined(separator: ", ")
            let level: SetupRow.Level
            let detail: String
            if installed.isEmpty {
                level = .good
                detail = String(localized: "bd's git hooks aren't installed, so beads never ride in a commit. Sharing doesn't need them.", bundle: .module)
            } else if installed.contains(where: \.isOutdated) {
                level = .attention
                detail = String(localized: "bd's git hooks are installed (\(names)) and at least one is from an older bd. bd hooks install refreshes them.", bundle: .module, comment: "Hook names")
            } else if setup.exportsIssuesFile == true {
                level = .info
                detail = String(localized: "bd's git hooks are installed (\(names)), and bd keeps .beads/issues.jsonl current, so the pre-commit hook adds that file to commits. Sharing doesn't need either.", bundle: .module, comment: "Hook names")
            } else {
                level = .info
                detail = String(localized: "bd's git hooks are installed (\(names)). They add nothing about beads to commits while export.auto is off.", bundle: .module, comment: "Hook names")
            }
            rows.append(SetupRow(
                kind: .commits, level: level,
                title: String(localized: "Commits", bundle: .module, comment: "Workspace Setup row: git hooks"),
                detail: detail, action: nil
            ))
        }

        // bd
        if let context = setup.context, let version = context.bdVersion {
            let detail = context.role.map {
                String(localized: "Version \(version), as \($0). Everyone sharing a database should run the same version; bd refuses to mix them.", bundle: .module, comment: "bd's version, then the role: maintainer or contributor")
            } ?? String(localized: "Version \(version). Everyone sharing a database should run the same version; bd refuses to mix them.", bundle: .module, comment: "bd's version")
            rows.append(SetupRow(kind: .bd, level: .good, title: "bd", detail: detail, action: nil))
        }
        return rows
    }
}

extension String {
    /// The phrase with its first letter capitalised, for starting a sentence with one that was
    /// written to follow other words.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// A sharing failure for the Changes menu, carrying bd's words as its description.
struct SharingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
