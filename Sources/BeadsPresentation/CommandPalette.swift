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
    case showView(ViewSource)
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
    case chooseTheme
    case setTextSize(TextSize)

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
        case .showView(let source): "view-\(Self.viewKey(source))"
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
        case .chooseTheme: "choose-theme"
        case .setTextSize(let size): "text-size-\(size.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .openWorkspace: "Open Beads Workspace…"
        case .closeWorkspace: "Close Workspace"
        case .refresh: "Refresh from bd"
        case .newBead: "New Bead"
        case .editSelected: "Edit Selected Bead"
        case .focusSearch: "Find in This View"
        case .addFilter: "Add Filter"
        case .clearFilters: "Clear Filters"
        case .displayOptions: "Display Options"
        case .toggleDetails: "Toggle Details Panel"
        case .showShortcuts: "Keyboard Shortcuts"
        case .showView(let source): "Go to \(Self.viewTitle(source))"
        case .setLayout(let layout): "Show as \(layout.rawValue.capitalized)"
        case .setGrouping(let grouping): "Group by \(DisplayText.grouping(grouping))"
        case .setOrdering(let sort): "Order by \(DisplayText.sort(sort))"
        case .goToIssue(let id, let title): "\(id.rawValue) \(title)"
        case .toggleMark(let mark): "Toggle \(mark == .pinned ? "Pin" : "Star")"
        case .showGraph: "Show Dependency Graph"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .focusSelected: "Focus on Selected Bead"
        case .unfocus: "Leave Focused View"
        case .expandAll: "Expand All"
        case .collapseAll: "Collapse All"
        case .toggleColumn(let column): "Column: \(column.title)"
        case .resetColumns: "Reset Columns"
        case .openSettings: "Settings…"
        case .chooseTheme: "Theme…"
        case .setTextSize(let size): "Text Size: \(size.title)"
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
        case .showView: ["go", "switch", "view"]
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
        case .goBack: ["back", "previous", "return", "undo navigation"]
        case .goForward: ["forward", "next", "again"]
        case .toggleMark(let mark): mark == .pinned
            ? ["pin", "unpin", "pinned", "top", "stick", "selected bead"]
            : ["star", "unstar", "starred", "flag", "unflag", "favourite", "favorite", "bookmark", "selected bead"]
        case .chooseTheme: ["theme", "themes", "colour", "color", "appearance", "dark mode",
                            "light mode", "contrast", "dracula", "nord", "solarized"]
        case .setTextSize: ["text", "font", "bigger", "larger", "smaller", "size", "accessibility", "eyesight"]
        }
    }

    /// The section it appears under in the palette and the shortcut sheet.
    public var group: String {
        switch self {
        case .openWorkspace, .closeWorkspace, .refresh: "Workspace"
        case .newBead, .editSelected, .toggleMark, .showGraph: "Beads"
        case .focusSearch, .addFilter, .clearFilters: "Find"
        case .displayOptions, .toggleDetails, .setLayout, .setGrouping, .setOrdering,
             .expandAll, .collapseAll, .toggleColumn, .resetColumns: "Display"
        case .focusSelected, .unfocus: "Views"
        case .openSettings: "Appearance"
        case .showShortcuts: "Help"
        case .showView, .goBack, .goForward: "Views"
        case .goToIssue: "Beads"
        case .chooseTheme, .setTextSize: "Appearance"
        }
    }

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
        case .showView, .setGrouping, .setOrdering, .goToIssue, .setTextSize, .focusSelected,
             .unfocus, .expandAll, .collapseAll, .toggleColumn, .resetColumns: []
        }
    }

    /// How the keys are written in the palette and the shortcut sheet.
    public var shortcut: String? {
        let keys = bindings.map(\.display)
        return keys.isEmpty ? nil : keys.joined(separator: " or ")
    }

    static func viewKey(_ source: ViewSource) -> String {
        switch source {
        case .lifecycle(let scope): scope.rawValue
        case .focused(let id): id.rawValue
        case .label(let label): label
        }
    }

    /// The palette names a view the way the sidebar does; an epic view by its bead.
    static func viewTitle(_ source: ViewSource) -> String {
        switch source {
        case .lifecycle(let scope): DisplayText.scope(scope)
        case .focused(let id): id.rawValue
        case .label(let label): IssueMark(rawValue: label)?.title ?? label
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
        var commands: [AppCommand] = [.openWorkspace, .refresh]
        if model.canEdit { commands.append(.newBead) }
        if model.canEdit, model.selection != nil {
            commands.append(.editSelected)
            commands += IssueMark.allCases.map { .toggleMark($0) }
        }
        if model.selection != nil { commands.append(.showGraph) }
        if model.canGoBack { commands.append(.goBack) }
        if model.canGoForward { commands.append(.goForward) }
        if let id = model.selection, model.snapshot?.children(of: id).isEmpty == false {
            commands.append(.focusSelected)
        }
        if case .focused = model.source { commands.append(.unfocus) }
        if model.layout == .tree { commands += [.expandAll, .collapseAll] }
        if model.layout == .list {
            commands += ListColumn.allCases.filter { !$0.isAlwaysVisible }.map { .toggleColumn($0) }
            commands.append(.resetColumns)
        }
        commands.append(.openSettings)
        if !model.filter.isEmpty || !model.searchText.isEmpty { commands.append(.clearFilters) }
        commands.append(.closeWorkspace)
        commands += Scope.allCases.map { .showView(.lifecycle($0)) }
        if model.hasStarredBeads { commands.append(.showView(.label(IssueMark.starred.label))) }
        commands += [.focusSearch, .addFilter]
        commands += WorkspaceModel.Layout.allCases.map { .setLayout($0) }
        commands += IssueGrouping.allCases.map { .setGrouping($0) }
        commands += IssueSort.allCases.map { .setOrdering($0) }
        commands += [.displayOptions, .toggleDetails, .chooseTheme]
        commands += TextSize.allCases.map { .setTextSize($0) }
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
