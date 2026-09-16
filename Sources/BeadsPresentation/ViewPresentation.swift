import BeadsCore

/// What a view remembers while you're elsewhere: its filters and how it's displayed.
public struct ViewState: Equatable, Sendable {
    public var filter: ViewFilter
    public var layout: WorkspaceModel.Layout
    public var grouping: IssueGrouping
    public var ordering: IssueSort

    public init(filter: ViewFilter, layout: WorkspaceModel.Layout, grouping: IssueGrouping, ordering: IssueSort) {
        self.filter = filter
        self.layout = layout
        self.grouping = grouping
        self.ordering = ordering
    }

    /// Where each view starts: epics as a tree, All grouped by lifecycle, In Flight by status.
    public static func defaults(for source: ViewSource) -> ViewState {
        switch source {
        case .lifecycle(let scope):
            let grouping: IssueGrouping = switch scope {
            case .all: .category
            case .inFlight: .status
            case .open, .ready, .blocked, .deferred, .closed: .none
            }
            return ViewState(filter: ViewFilter(), layout: .list, grouping: grouping, ordering: scope.defaultSort)
        case .focused:
            return ViewState(filter: ViewFilter(), layout: .tree, grouping: .category, ordering: .priority)
        }
    }
}

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

    public var id: FilterField { field }
}

public struct FilterMenuOption: Identifiable, Equatable, Sendable {
    public let value: String
    public let title: String
    public let count: Int
    public let isSelected: Bool

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

/// A view in the sidebar.
public struct SidebarEntry: Identifiable, Equatable, Sendable {
    public let source: ViewSource
    public let title: String
    /// The view's total, before any filter.
    public let count: Int

    public var id: ViewSource { source }
}

public extension Scope {
    var defaultSort: IssueSort {
        switch self {
        case .closed: .recentlyClosed
        case .inFlight, .all: .recentlyUpdated
        case .open, .ready, .blocked, .deferred: .priority
        }
    }
}
