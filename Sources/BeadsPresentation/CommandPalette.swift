import BeadsCore
import Foundation

/// A key that runs a command. The app has one of these per binding, and both the menu bar and
/// the palette read them, so a key can't be advertised in one place and bound in another.
public struct KeyBinding: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
    }

    public let key: Character
    public let modifiers: Modifiers

    public init(_ key: Character, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Written the way macOS writes it: ⌥⇧⌘ in that order, then the key.
    public var display: String {
        var text = ""
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + String(key).uppercased()
    }

    /// A key with no ⌘ behind it, which a text field would otherwise swallow.
    public var isPlainKey: Bool { !modifiers.contains(.command) }
}

/// Everything the app can be asked to do from the keyboard: the ⌘P palette lists these, the
/// shortcut sheet documents them, and the views carry them out. Keeping them in one enum means
/// a new action can't quietly exist without a name, a place and a key.
public enum AppCommand: Equatable, Sendable, Identifiable {
    case openWorkspace
    case closeWorkspace
    case refresh
    case newBead
    case editSelected
    case focusSearch
    case addFilter
    case clearFilters
    case displayOptions
    case toggleDetails
    case showShortcuts
    case showView(IssueView.ID)
    case saveView
    case saveViewAs
    case resetView
    case exportView(IssueView.ID)
    case importViews
    case setLayout(WorkspaceModel.Layout)
    case setGrouping(IssueGrouping)
    case setOrdering(IssueSort)
    case goToIssue(IssueID, title: String)
    case toggleMark(IssueMark)
    case showGraph
    case goBack
    case goForward
    case focusSelected
    case unfocus
    case expandAll
    case collapseAll
    case toggleColumn(ListColumn)
    case resetColumns
    case openSettings
    case resetConfiguration
    case backUpNow
    case setUpBackup
    case turnOnJournal
    case setSidebarStyle(SidebarStyle)
    case chooseTheme
    case setTextSize(TextSize)
    /// A language Beady ships with, or nil for the system's; takes effect after a relaunch.
    case setLanguage(String?)

    public var id: String {
        switch self {
        case .openWorkspace: "open-workspace"
        case .closeWorkspace: "close-workspace"
        case .refresh: "refresh"
        case .newBead: "new-bead"
        case .editSelected: "edit-selected"
        case .focusSearch: "focus-search"
        case .addFilter: "add-filter"
        case .clearFilters: "clear-filters"
        case .displayOptions: "display-options"
        case .toggleDetails: "toggle-details"
        case .showShortcuts: "show-shortcuts"
        case .showView(let id): "view-\(id.rawValue)"
        case .saveView: "save-view"
        case .saveViewAs: "save-view-as"
        case .resetView: "reset-view"
        case .exportView(let id): "export-\(id.rawValue)"
        case .importViews: "import-views"
        case .setLayout(let layout): "layout-\(layout.rawValue)"
        case .setGrouping(let grouping): "group-\(grouping.rawValue)"
        case .setOrdering(let sort): "sort-\(sort.rawValue)"
        case .goToIssue(let id, _): "go-\(id.rawValue)"
        case .toggleMark(let mark): "mark-\(mark.rawValue)"
        case .showGraph: "show-graph"
        case .goBack: "go-back"
        case .goForward: "go-forward"
        case .focusSelected: "focus-selected"
        case .unfocus: "unfocus"
        case .expandAll: "expand-all"
        case .collapseAll: "collapse-all"
        case .toggleColumn(let column): "column-\(column.id)"
        case .resetColumns: "reset-columns"
        case .openSettings: "open-settings"
        case .resetConfiguration: "reset-configuration"
        case .backUpNow: "back-up-now"
        case .setUpBackup: "set-up-backup"
        case .turnOnJournal: "turn-on-journal"
        case .setSidebarStyle(let style): "sidebar-\(style.rawValue)"
        case .chooseTheme: "choose-theme"
        case .setTextSize(let size): "text-size-\(size.rawValue)"
        case .setLanguage(let code): "language-\(code ?? "system")"
        }
    }

    public var title: String {
        switch self {
        case .openWorkspace: String(localized: "Open Beads Workspace…", bundle: .module, comment: "Command")
        case .closeWorkspace: String(localized: "Close Workspace", bundle: .module, comment: "Command")
        case .refresh: String(localized: "Refresh from bd", bundle: .module, comment: "Command")
        case .newBead: String(localized: "New Bead", bundle: .module, comment: "Command")
        case .editSelected: String(localized: "Edit Selected Bead", bundle: .module, comment: "Command")
        case .focusSearch: String(localized: "Find in This View", bundle: .module, comment: "Command")
        case .addFilter: String(localized: "Add Filter", bundle: .module, comment: "Command")
        case .clearFilters: String(localized: "Clear Filters", bundle: .module, comment: "Command")
        case .displayOptions: String(localized: "Display Options", bundle: .module, comment: "Command")
        case .toggleDetails: String(localized: "Toggle Details Panel", bundle: .module, comment: "Command")
        case .showShortcuts: String(localized: "Keyboard Shortcuts", bundle: .module, comment: "Command")
        case .showView(let id): String(localized: "Go to \(Self.viewName(id))", bundle: .module, comment: "Command; the value is a view's name")
        case .saveView: String(localized: "Save View", bundle: .module, comment: "Command")
        case .saveViewAs: String(localized: "Save as New View…", bundle: .module, comment: "Command")
        case .resetView: String(localized: "Reset View", bundle: .module, comment: "Command: back to the view as saved")
        case .exportView: String(localized: "Export View…", bundle: .module, comment: "Command")
        case .importViews: String(localized: "Import Views…", bundle: .module, comment: "Command")
        case .setLayout(let layout): String(localized: "Show as \(DisplayText.layout(layout))", bundle: .module, comment: "Command; the value is List, Board or Tree")
        case .setGrouping(let grouping): String(localized: "Group by \(DisplayText.grouping(grouping))", bundle: .module, comment: "Command; the value is a grouping such as Status")
        case .setOrdering(let sort): String(localized: "Order by \(DisplayText.sort(sort))", bundle: .module, comment: "Command; the value is an ordering such as Priority")
        case .goToIssue(let id, let title): "\(id.rawValue) \(title)"
        case .toggleMark(.pinned): String(localized: "Toggle Pin", bundle: .module, comment: "Command")
        case .toggleMark(.starred): String(localized: "Toggle Star", bundle: .module, comment: "Command")
        case .showGraph: String(localized: "Show Dependency Graph", bundle: .module, comment: "Command")
        case .goBack: String(localized: "Back", bundle: .module, comment: "Command: to the last bead looked at")
        case .goForward: String(localized: "Forward", bundle: .module, comment: "Command: to the bead come back from")
        case .focusSelected: String(localized: "Focus on Selected Bead", bundle: .module, comment: "Command: narrow the view to everything under it")
        case .unfocus: String(localized: "Leave Focused View", bundle: .module, comment: "Command")
        case .expandAll: String(localized: "Expand All", bundle: .module, comment: "Command, in the tree")
        case .collapseAll: String(localized: "Collapse All", bundle: .module, comment: "Command, in the tree")
        case .toggleColumn(let column): String(localized: "Column: \(column.title)", bundle: .module, comment: "Command: show or hide a list column; the value is its header")
        case .resetColumns: String(localized: "Reset Columns", bundle: .module, comment: "Command")
        case .openSettings: String(localized: "Settings…", bundle: .module, comment: "Command")
        case .resetConfiguration: String(localized: "Reset Configuration…", bundle: .module, comment: "Command")
        case .backUpNow: String(localized: "Back Up Now", bundle: .module, comment: "Command")
        case .setUpBackup: String(localized: "Set Up Backup…", bundle: .module, comment: "Command")
        case .turnOnJournal: String(localized: "Turn On bd's Change Journal", bundle: .module, comment: "Command")
        case .setSidebarStyle(let style): String(localized: "Sidebar: \(style.title)", bundle: .module, comment: "Command; the value is Themed or Translucent")
        case .chooseTheme: String(localized: "Theme…", bundle: .module, comment: "Command")
        case .setTextSize(let size): String(localized: "Text Size: \(size.title)", bundle: .module, comment: "Command; the value is a text size such as Large")
        case .setLanguage(let code): String(localized: "Language: \(LanguageSetting.title(for: code))", bundle: .module, comment: "Command; the value is a language name, or System Default")
        }
    }

    /// Other words that should find this command. A palette is only as good as the words it
    /// answers to: "fin" has to reach Find, "kanban" has to reach the board.
    public var keywords: [String] {
        switch self {
        case .openWorkspace: ["open", "workspace", "project", "database", "folder"]
        case .closeWorkspace: ["close", "quit workspace"]
        case .refresh: ["reload", "sync", "update", "fetch"]
        case .newBead: ["create", "add", "issue", "task"]
        case .editSelected: ["change", "rename", "modify", "title", "description"]
        case .focusSearch: ["find", "search", "text", "look for"]
        case .addFilter: ["filter", "narrow", "where", "status", "priority", "label", "assignee"]
        case .clearFilters: ["reset", "remove filters", "show everything"]
        case .displayOptions: ["columns", "sort", "order", "group", "layout", "show"]
        case .toggleDetails: ["inspector", "side panel", "info"]
        case .showShortcuts: ["help", "keys", "keyboard", "shortcuts"]
        case .showView(let id): ["go", "switch", "view"] + Self.viewKeywords(id)
        case .saveView: ["save", "keep", "store", "filters", "layout"]
        case .saveViewAs: ["save as", "new view", "duplicate", "copy", "keep", "filters"]
        case .resetView: ["reset", "revert", "discard", "undo changes", "back to saved"]
        case .exportView: ["export", "share", "save as file", "beadyview", "send"]
        case .importViews: ["import", "open view", "beadyview", "file", "receive"]
        case .setLayout(let layout): layout == .board ? ["kanban", "columns", "swimlanes"] : ["view as", layout.rawValue]
        case .setGrouping: ["group", "section", "break down"]
        case .setOrdering: ["sort", "order", "arrange"]
        case .goToIssue: ["bead", "issue", "go to"]
        case .showGraph: ["graph", "dependencies", "blockers", "unblock", "chain", "why blocked"]
        case .focusSelected: ["focus", "subtree", "children", "zoom in", "scope"]
        case .unfocus: ["unfocus", "leave", "out", "back to view"]
        case .expandAll: ["expand", "open all", "unfold"]
        case .collapseAll: ["collapse", "fold", "close all"]
        case .toggleColumn: ["column", "show", "hide", "table"]
        case .resetColumns: ["columns", "reset", "default widths"]
        case .openSettings: ["settings", "preferences", "options", "text size"]
        case .resetConfiguration: ["reset", "configuration", "settings", "defaults", "preferences", "clean", "uninstall", "start over", "fresh install"]
        case .backUpNow: ["backup", "back up", "sync", "save", "copy", "dolt"]
        case .setUpBackup: ["backup", "back up", "configure backup", "destination", "folder"]
        case .turnOnJournal: ["journal", "events", "live", "activity", "who changed", "agents", "watch"]
        case .setSidebarStyle: ["sidebar", "translucent", "vibrancy", "material", "native"]
        case .goBack: ["back", "previous", "return", "undo navigation"]
        case .goForward: ["forward", "next", "again"]
        case .toggleMark(let mark): mark == .pinned
            ? ["pin", "unpin", "pinned", "top", "stick", "selected bead"]
            : ["star", "unstar", "starred", "flag", "unflag", "favourite", "favorite", "bookmark", "selected bead"]
        case .chooseTheme: ["theme", "themes", "colour", "color", "appearance", "dark mode",
                            "light mode", "contrast", "dracula", "nord", "solarized"]
        case .setTextSize: ["text", "font", "bigger", "larger", "smaller", "size", "accessibility", "eyesight"]
        case .setLanguage(let code): ["language", "locale", "translation", "english"] + (code.map { [$0, LanguageSetting.displayName($0, in: Locale(identifier: "en"))] } ?? ["system", "default"])
        }
    }

    /// The section it appears under in the palette and the shortcut sheet.
    public var group: String {
        switch self {
        case .openWorkspace, .closeWorkspace, .refresh, .backUpNow, .setUpBackup, .turnOnJournal: String(localized: "Workspace", bundle: .module, comment: "Command group")
        case .newBead, .editSelected, .toggleMark, .showGraph: Self.beadsGroup
        case .focusSearch, .addFilter, .clearFilters: String(localized: "Find", bundle: .module, comment: "Command group")
        case .displayOptions, .toggleDetails, .setLayout, .setGrouping, .setOrdering,
             .expandAll, .collapseAll, .toggleColumn, .resetColumns: String(localized: "Display", bundle: .module, comment: "Command group")
        case .focusSelected, .unfocus, .saveView, .saveViewAs, .resetView, .exportView, .importViews: Self.viewsGroup
        case .openSettings, .setSidebarStyle, .resetConfiguration: Self.appearanceGroup
        case .showShortcuts: String(localized: "Help", bundle: .module, comment: "Command group")
        case .showView, .goBack, .goForward: Self.viewsGroup
        case .goToIssue: Self.beadsGroup
        case .chooseTheme, .setTextSize, .setLanguage: Self.appearanceGroup
        }
    }

    private static var beadsGroup: String { String(localized: "Beads", bundle: .module, comment: "Command group") }
    private static var viewsGroup: String { String(localized: "Views", bundle: .module, comment: "Command group") }
    private static var appearanceGroup: String { String(localized: "Appearance", bundle: .module, comment: "Command group") }

    /// The keys that run this command. The first is the one the palette leads with; a command
    /// with both a plain key and a ⌘ key has the plain one first, as Linear does.
    public var bindings: [KeyBinding] {
        switch self {
        case .openWorkspace: [KeyBinding("o", .command)]
        case .closeWorkspace: [KeyBinding("w", [.command, .shift])]
        case .refresh: [KeyBinding("r", .command)]
        case .newBead: [KeyBinding("n", .command)]
        case .editSelected: [KeyBinding("e", .command)]
        case .focusSearch: [KeyBinding("/"), KeyBinding("f", .command)]
        case .addFilter: [KeyBinding("f"), KeyBinding("f", [.command, .option])]
        case .clearFilters: [KeyBinding("f", [.command, .shift])]
        case .displayOptions: [KeyBinding("v", .shift), KeyBinding("d", [.command, .shift])]
        case .toggleDetails: [KeyBinding("i", .command)]
        case .showShortcuts: [KeyBinding("?"), KeyBinding("/", .command)]
        case .setLayout(let layout): [KeyBinding(Character("\(layoutNumber(layout))"), .command)]
        case .toggleMark(let mark): [KeyBinding(mark == .pinned ? "p" : "s", [.command, .shift])]
        case .showGraph: [KeyBinding("g", .command)]
        case .openSettings: [KeyBinding(",", .command)]
        case .goBack: [KeyBinding("[", .command)]
        case .goForward: [KeyBinding("]", .command)]
        case .chooseTheme: [KeyBinding("t", .command)]
        case .saveView: [KeyBinding("s", .command)]
        case .saveViewAs: [KeyBinding("s", [.command, .option])]
        case .resetView: [KeyBinding("r", [.command, .option])]
        case .showView, .setGrouping, .setOrdering, .goToIssue, .setTextSize, .focusSelected, .exportView, .importViews, .resetConfiguration,
             .unfocus, .expandAll, .collapseAll, .toggleColumn, .resetColumns, .setSidebarStyle,
             .backUpNow, .setUpBackup, .turnOnJournal, .setLanguage: []
        }
    }

    /// How the keys are written in the palette and the shortcut sheet.
    public var shortcut: String? {
        let keys = bindings.map(\.display)
        guard let first = keys.first else { return nil }
        return keys.dropFirst().reduce(first) { String(localized: "\($0) or \($1)", bundle: .module, comment: "Two keys that both run a command, such as ‘/ or ⌘F’") }
    }

    /// The palette names a view the way the sidebar does.
    static func viewName(_ id: IssueView.ID) -> String {
        IssueView.builtIn(id)?.name ?? id.rawValue
    }

    /// bd's own word for what a built-in shows, so "blocked" finds Stuck; Ready keeps answering
    /// to Frontier, the name it shipped under.
    static func viewKeywords(_ id: IssueView.ID) -> [String] {
        switch id {
        case .frontier: ["ready", "frontier", "available", "unblocked", "next"]
        case .inFlight: ["wip", "in progress", "working", "started"]
        case .stuck: ["blocked", "waiting", "blockers"]
        case .pipeline: ["board", "kanban", "lifecycle", "all"]
        case .recent: ["updated", "today", "activity", "changed"]
        case .landed: ["closed", "done", "finished", "shipped"]
        case .deferred: ["frozen", "later", "snoozed", "deferred"]
        case .everything: ["all", "every bead"]
        case .starred: ["star", "starred", "favourite", "favorite"]
        default: []
        }
    }

    public var isGoToIssue: Bool {
        if case .goToIssue = self { return true }
        return false
    }

    private func layoutNumber(_ layout: WorkspaceModel.Layout) -> Int {
        (WorkspaceModel.Layout.allCases.firstIndex(of: layout) ?? 0) + 1
    }
}

/// Builds and ranks what the palette shows.
public enum CommandCatalog {
    /// The commands available right now, in the order the palette shows them unfiltered. A
    /// command that would do nothing — editing with no selection, creating in a read-only
    /// workspace — isn't offered, so nothing in the list is a dead end.
    @MainActor
    public static func all(for model: WorkspaceModel) -> [AppCommand] {
        let backup = model.backup
        var commands: [AppCommand] = [.openWorkspace, .refresh]
        if model.canEdit { commands.append(.newBead) }
        if model.canEdit, model.selection != nil {
            commands.append(.editSelected)
            commands += IssueMark.allCases.map { .toggleMark($0) }
        }
        // The graph is a whole-database view now, so it doesn't need a selection to open.
        commands.append(.showGraph)
        if model.canGoBack { commands.append(.goBack) }
        if model.canGoForward { commands.append(.goForward) }
        if let id = model.selection, model.snapshot?.children(of: id).isEmpty == false {
            commands.append(.focusSelected)
        }
        if model.focusedIssue != nil { commands.append(.unfocus) }
        // Only while there is something to save or throw away; Save only where it would stick.
        if model.isModified {
            if model.canSave { commands.append(.saveView) }
            commands += [.saveViewAs, .resetView]
        }
        commands += [.exportView(model.viewID), .importViews]
        if model.presentedLayout == .tree { commands += [.expandAll, .collapseAll] }
        if model.presentedLayout == .list {
            commands += ListColumn.allCases.filter { !$0.isAlwaysVisible }.map { .toggleColumn($0) }
            commands.append(.resetColumns)
        }
        commands += SidebarStyle.allCases.map { .setSidebarStyle($0) }
        commands += [.openSettings, .resetConfiguration]
        if model.hasClearableFilters || !model.searchText.isEmpty { commands.append(.clearFilters) }
        commands.append(backup.isConfigured ? .backUpNow : .setUpBackup)
        // With the setting off, or after an Undo: the palette is where a change of mind goes.
        if model.canEdit, model.journal.canBeTurnedOn { commands.append(.turnOnJournal) }
        commands.append(.closeWorkspace)
        // The sidebar's rows, Starred included only once something is starred.
        commands += model.sidebarViews.map { .showView($0.id) }
        commands += [.focusSearch, .addFilter]
        commands += WorkspaceModel.Layout.allCases.map { .setLayout($0) }
        commands += IssueGrouping.allCases.map { .setGrouping($0) }
        commands += IssueSort.allCases.map { .setOrdering($0) }
        commands += [.displayOptions, .toggleDetails, .chooseTheme]
        commands += TextSize.allCases.map { .setTextSize($0) }
        commands += LanguageSetting.choices.map { .setLanguage($0) }
        commands.append(.showShortcuts)
        return commands
    }

    /// What to show for what the user has typed: matching commands first, then matching beads.
    @MainActor
    public static func results(for query: String, model: WorkspaceModel, limit: Int = 8) -> [AppCommand] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all(for: model) }

        // One or two letters can't mean a word, so they filter on what's written on screen.
        // Any more, and aliases come into play — "fin" should find Find, "kanban" the board.
        let aliasesCount = query.trimmingCharacters(in: .whitespaces).count >= 3
        let commands = all(for: model)
            .compactMap { command -> (AppCommand, Int)? in
                if let score = score(command.title, words) { return (command, score) }
                guard aliasesCount else { return nil }
                // An alias still finds the command, but never outranks a match on its name.
                guard let score = score(command.keywords.joined(separator: " "), words) else { return nil }
                return (command, max(1, score - 3))
            }
            .sorted { ($1.1, $1.0.title.count) < ($0.1, $0.0.title.count) }
            .map(\.0)

        let beads = (model.snapshot?.issues ?? [])
            .compactMap { issue -> (AppCommand, Int)? in
                let haystack = "\(issue.id.rawValue) \(issue.title)"
                guard let score = score(haystack, words) else { return nil }
                // An id the user typed out is what they meant; put it above the commands.
                let exactID = issue.id.rawValue.lowercased() == query.lowercased() ? 1000 : 0
                return (.goToIssue(issue.id, title: issue.title), score + exactID)
            }
            .sorted { ($1.1, $1.0.title.count) < ($0.1, $0.0.title.count) }
            .prefix(limit)

        let leading = beads.filter { $0.1 >= 1000 }.map(\.0)
        let trailing = beads.filter { $0.1 < 1000 }.map(\.0)
        return leading + commands + trailing
    }

    /// Every word has to appear; whole words and prefixes score higher than a match mid-word,
    /// so "board" finds "Show as Board" before "Keyboard Shortcuts".
    private static func score(_ text: String, _ words: [String]) -> Int? {
        let haystack = text.lowercased()
        let parts = haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var total = 0
        for word in words {
            if haystack.hasPrefix(word) {
                total += 6
            } else if parts.contains(where: { $0 == word }) {
                total += 5
            } else if parts.contains(where: { $0.hasPrefix(word) }) {
                total += 4
            } else if haystack.contains(word) {
                total += 2
            } else {
                return nil
            }
        }
        return total
    }
}
