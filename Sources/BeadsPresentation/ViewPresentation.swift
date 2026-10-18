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

/// A view in the sidebar.
public struct SidebarEntry: Identifiable, Equatable, Sendable {
    public let id: IssueView.ID
    public let title: String
    /// An SF Symbol name.
    public let symbol: String
    /// What the view's own filter matches, whatever has been added to it.
    public let count: Int
    /// What the view means in bd, for hovering the row; empty when the name says it all.
    public let help: String
}
