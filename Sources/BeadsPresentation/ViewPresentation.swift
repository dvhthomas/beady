import BeadsCore

/// What a view remembers while you're elsewhere: its filters and how it's displayed.
public struct ViewState: Equatable, Codable, Sendable {
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

    /// Where a view starts: its own filter and presentation.
    public static func defaults(for view: IssueView) -> ViewState {
        ViewState(
            filter: view.filter,
            layout: view.presentation.layout,
            grouping: view.presentation.grouping,
            ordering: view.presentation.ordering
        )
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
    public let id: IssueView.ID
    public let title: String
    /// An SF Symbol name.
    public let symbol: String
    /// What the view's own filter matches, whatever has been added to it.
    public let count: Int
    /// What the view means in bd, for hovering the row; empty when the name says it all.
    /// Filled in by the hover-help work (bdv-jlx.11).
    public let help: String
}

/// A view's id and its state, as one record: a dictionary keyed by a struct doesn't encode as
/// a JSON object.
struct SavedViewState: Codable, Sendable {
    let view: IssueView.ID
    let state: ViewState
}
