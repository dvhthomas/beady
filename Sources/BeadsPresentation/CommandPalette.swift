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
        }
    }

    public var title: String {
        switch self {
        case .openWorkspace: "Open Beads Workspace…"
        case .closeWorkspace: "Close Workspace"
        case .refresh: "Refresh from bd"
        case .newBead: "New Bead"
        case .editSelected: "Edit Selected Bead"
        case .focusSearch: "Search This View"
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
        }
    }

    /// The section it appears under in the palette and the shortcut sheet.
    public var group: String {
        switch self {
        case .openWorkspace, .closeWorkspace, .refresh: "Workspace"
        case .newBead, .editSelected: "Beads"
        case .focusSearch, .addFilter, .clearFilters: "Find"
        case .displayOptions, .toggleDetails, .setLayout, .setGrouping, .setOrdering: "Display"
        case .showShortcuts: "Help"
        case .showView: "Views"
        case .goToIssue: "Beads"
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
        case .showView, .setGrouping, .setOrdering, .goToIssue: []
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
        }
    }

    /// The palette names a view the way the sidebar does; an epic view by its bead.
    static func viewTitle(_ source: ViewSource) -> String {
        switch source {
        case .lifecycle(let scope): DisplayText.scope(scope)
        case .focused(let id): id.rawValue
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
        if model.canEdit, model.selection != nil { commands.append(.editSelected) }
        if !model.filter.isEmpty || !model.searchText.isEmpty { commands.append(.clearFilters) }
        commands.append(.closeWorkspace)
        commands += Scope.allCases.map { .showView(.lifecycle($0)) }
        commands += [.focusSearch, .addFilter]
        commands += WorkspaceModel.Layout.allCases.map { .setLayout($0) }
        commands += IssueGrouping.allCases.map { .setGrouping($0) }
        commands += IssueSort.allCases.map { .setOrdering($0) }
        commands += [.displayOptions, .toggleDetails, .showShortcuts]
        return commands
    }

    /// What to show for what the user has typed: matching commands first, then matching beads.
    @MainActor
    public static func results(for query: String, model: WorkspaceModel, limit: Int = 8) -> [AppCommand] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all(for: model) }

        let commands = all(for: model)
            .compactMap { command -> (AppCommand, Int)? in
                guard let score = score(command.title, words) else { return nil }
                return (command, score)
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
