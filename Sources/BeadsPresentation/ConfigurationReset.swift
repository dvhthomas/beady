import Foundation

/// Everything Beady keeps per user, and nothing it wrote into a workspace: what Reset
/// Configuration removes, as the sheet lists it, with counts. The one list of the preferences
/// keys the app writes lives here, and a test reads the code to hold it to that.
public struct ConfigurationInventory: Equatable, Sendable {
    public static let preferencesDomain = "me.bitsby.beady"
    public static let libraryFolder = "~/Library/Application Support/Beady"

    public enum Group: CaseIterable, Sendable {
        case workspaces, views, appearance, language, window, journal
    }

    /// Every preferences key Beady writes, by what it is for. Legacy keys stay listed as long as
    /// the code still reads them, so a reset clears them too.
    public static let knownKeys: [Group: Set<String>] = [
        .workspaces: ["recentWorkspaces"],
        .views: ["views", "liveViews", "offeredViews", "viewStates", "view", "scope", "collapsedSidebarSections"],
        .appearance: ["appearance", "darkTheme", "lightTheme", "textSize", "sidebarStyle"],
        // The per-app language, under the key macOS itself uses (System Settings writes the same one).
        .language: [LanguageSetting.key],
        .window: ["issueListColumns", "inspectorWidth"],
        .journal: ["turnsOnEventsJournal", "eventsJournalTurnedOn"],
    ]

    public static var allKnownKeys: Set<String> {
        knownKeys.values.reduce(into: []) { $0.formUnion($1) }
    }

    /// What is not touched, in the sheet's own words.
    public static var leavesAlone: String {
        String(localized: "Nothing Beady wrote into a workspace is touched: bd's change-journal setting lives in that workspace's .beads/config.yaml and stays as it is.", bundle: .module)
    }

    public struct Line: Equatable, Sendable, Identifiable {
        public let title: String
        public let detail: String
        public var id: String { title }
    }

    public let lines: [Line]
    /// The user's own views in the Library folder.
    public let libraryViews: Int

    /// - Parameters:
    ///   - presentKeys: the keys in Beady's preferences domain right now, whoever wrote them.
    ///   - recentWorkspaces: how many workspaces are remembered.
    ///   - journalWorkspaces: how many workspaces Beady turned bd's journal on in.
    ///   - libraryViews: the user's own views in the Library folder.
    public init(presentKeys: Set<String>, recentWorkspaces: Int, journalWorkspaces: Int, libraryViews: Int) {
        func has(_ group: Group) -> Bool { !presentKeys.isDisjoint(with: Self.knownKeys[group] ?? []) }
        var lines: [Line] = []
        if has(.workspaces) { lines.append(Line(title: String(localized: "Remembered workspaces", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: "\(recentWorkspaces)")) }
        if has(.views) { lines.append(Line(title: String(localized: "Views", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: String(localized: "filters, layouts and which view was open", bundle: .module, comment: "Reset Configuration: detail of the Views line"))) }
        lines.append(Line(title: String(localized: "Saved views in the Library", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: libraryViews == 0 ? String(localized: "none", bundle: .module, comment: "Reset Configuration: no saved views") : "\(libraryViews)"))
        if has(.appearance) { lines.append(Line(title: String(localized: "Appearance", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: String(localized: "theme, text size and sidebar style", bundle: .module, comment: "Reset Configuration: detail of the Appearance line"))) }
        if has(.language) { lines.append(Line(title: String(localized: "Language", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: String(localized: "back to the system language", bundle: .module, comment: "Reset Configuration: detail of the Language line"))) }
        if has(.window) { lines.append(Line(title: String(localized: "Window layout", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: String(localized: "columns and the details pane width", bundle: .module, comment: "Reset Configuration: detail of the Window layout line"))) }
        if has(.journal) {
            let workspaces = String(localized: "\(journalWorkspaces) workspaces", bundle: .module, comment: "Plural: how many workspaces the journal was turned on in")
            lines.append(Line(title: String(localized: "Change journal", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: String(localized: "the setting, and \(workspaces) it was turned on in", bundle: .module, comment: "Reset Configuration: detail of the Change journal line; the value is ‘N workspaces’")))
        }
        // Anything else in the domain, such as what AppKit remembers about open panels, goes
        // with it: a clean install has none of it either.
        let other = presentKeys.subtracting(Self.allKnownKeys).count
        if other > 0 { lines.append(Line(title: String(localized: "Other settings", bundle: .module, comment: "Reset Configuration: a line of what goes"), detail: "\(other)")) }
        self.lines = lines
        self.libraryViews = libraryViews
    }

    /// Nothing but the Library line, and that says none.
    public var isEmpty: Bool {
        lines.count == 1 && libraryViews == 0
    }

    public func plan(deletingLibrary: Bool) -> ResetPlan {
        ResetPlan(removesPreferences: true, removesLibrary: deletingLibrary)
    }

    /// The same reset from Terminal.
    public func commands(deletingLibrary: Bool) -> [String] {
        var commands = ["defaults delete \(Self.preferencesDomain)"]
        if deletingLibrary { commands.append("rm -rf \(Self.libraryFolder.replacingOccurrences(of: " ", with: "\\ "))") }
        return commands
    }
}

public struct ResetPlan: Equatable, Sendable {
    public let removesPreferences: Bool
    public let removesLibrary: Bool

    public init(removesPreferences: Bool, removesLibrary: Bool) {
        self.removesPreferences = removesPreferences
        self.removesLibrary = removesLibrary
    }
}

public enum ConfigurationReset {
    /// Carries a plan out: removes the whole preferences domain, and the Library folder when the
    /// plan says so. A Library that was never created is not an error.
    public static func perform(_ plan: ResetPlan, defaults: UserDefaults, domain: String, libraryFolder: URL?) throws {
        if plan.removesPreferences {
            defaults.removePersistentDomain(forName: domain)
            defaults.synchronize()
        }
        if plan.removesLibrary, let libraryFolder, FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.removeItem(at: libraryFolder)
        }
    }
}
