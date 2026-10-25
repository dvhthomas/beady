import BeadsCore

public struct OperatorChoice: Identifiable, Equatable, Sendable {
    public let op: FilterOperator
    public let title: String
    public let isSelected: Bool

    public var id: FilterOperator { op }
}

/// One filter chip: `field · operator · values · ✕`, as in Linear.
public struct FilterChipModel: Identifiable, Equatable, Sendable {
    public let field: FilterField
    public let fieldTitle: String
    public let operatorTitle: String
    /// Empty when the operator says it all (Blocked · yes).
    public let valuesTitle: String
    public let operators: [OperatorChoice]
    /// Part of what a built-in view means: shown with a lock, no ✕ and no operator menu, and
    /// Clear leaves it alone. Duplicate the view to change it.
    public let isLocked: Bool
    /// What the field means in bd, for hovering the field name.
    public let fieldHelp: String
    /// What the one chosen value means in bd, when there is one and it has a fixed meaning.
    public let valuesHelp: String?

    public var id: FilterField { field }
}

public struct FilterMenuOption: Identifiable, Equatable, Sendable {
    public let value: String
    public let title: String
    public let count: Int
    public let isSelected: Bool
    /// What the value means in bd, when it has a fixed meaning.
    public let help: String?

    public var id: String { value }
}

public struct IssueGroupModel: Identifiable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let issues: [Issue]
    /// Set when the group is itself a bead (grouping by parent), so the header can show progress.
    public let completion: Completion?

    public init(key: String, title: String, issues: [Issue], completion: Completion? = nil) {
        self.key = key
        self.title = title
        self.issues = issues
        self.completion = completion
    }

    public var id: String { key }
}

/// Where a user view's file lives: the user's own Library, or the open workspace's
/// `.beads/beady/views`, which travels with the repository.
public enum ViewTier: String, Sendable {
    case library, workspace
}

/// A view in the sidebar.
public struct SidebarEntry: Identifiable, Equatable, Sendable {
    public let id: IssueView.ID
    public let title: String
    /// The view's own SF Symbol name, which is what the row draws: never the layout glyph.
    public let symbol: String
    /// How the view is laid out right now, so you know before you click what you'll get.
    public let layout: ViewLayout
    /// What the view's own filter matches, whatever has been added to it.
    public let count: Int
    /// Whether what's live differs from the view as saved: the modified dot.
    public let isModified: Bool
    public let isBuiltIn: Bool
    /// What the view means in bd, for hovering the row; empty when the name says it all.
    public let help: String
    /// Where the view lives; a built-in counts as the Library's.
    public var tier: ViewTier = .library
}

/// One section of the sidebar: the built-ins, the user's own views, or Starred.
public struct SidebarSection: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case views, mine, workspace, starred
    }

    public let kind: Kind
    /// Empty for a section that is one row and needs no header.
    public let title: String
    public let entries: [SidebarEntry]
    /// Whether the header carries a + that saves the current view as a new one.
    public let canAdd: Bool

    public var id: Kind { kind }

    /// The tier a view dropped on this section moves to; nil where a drop means nothing.
    public var dropTier: ViewTier? {
        switch kind {
        case .mine: .library
        case .workspace: .workspace
        case .views, .starred: nil
        }
    }

    /// Whether collapsing the section would hide anything. The disclosure is always drawn, so the
    /// header never changes shape under the pointer; it is merely disabled when there is nothing
    /// to fold away.
    public var canCollapse: Bool { !entries.isEmpty }
}

/// What a dragged sidebar view carries. The private prefix means text dragged in from elsewhere
/// is never mistaken for a view being moved between tiers.
public enum ViewDragPayload {
    private static let prefix = "beady-view:"

    public static func encode(_ id: IssueView.ID) -> String {
        prefix + id.rawValue
    }

    /// The dragged view, only when exactly one of this app's payloads was dropped.
    public static func decode(_ items: [String]) -> IssueView.ID? {
        guard items.count == 1, let item = items.first, item.hasPrefix(prefix) else { return nil }
        let raw = String(item.dropFirst(prefix.count))
        return raw.isEmpty ? nil : IssueView.ID(raw)
    }
}
