import BeadsCore

// BeadsPresentation: UI-framework-free view state. Views bind to these types;
// everything that decides what is shown is tested here, not in SwiftUI.

public enum DisplayText {
    public static func status(_ raw: String) -> String {
        raw.split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public static func priority(_ priority: Int) -> String { "P\(priority)" }

    public static func window(_ window: TimeWindow) -> String {
        switch window {
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        }
    }

    public static func scope(_ scope: Scope) -> String {
        switch scope {
        case .all: "All"
        case .open: "Open"
        case .ready: "Ready"
        case .inFlight: "In Flight"
        case .blocked: "Blocked"
        case .deferred: "Deferred"
        case .closed: "Closed"
        }
    }

    public static func category(_ category: StatusCategory) -> String {
        switch category {
        case .active: "Open"
        case .wip: "In Flight"
        case .frozen: "Deferred"
        case .done: "Closed"
        }
    }

    public static func sort(_ sort: IssueSort) -> String {
        switch sort {
        case .priority: "Priority"
        case .recentlyUpdated: "Last updated"
        case .recentlyCreated: "Last created"
        case .recentlyClosed: "Last closed"
        case .issueID: "ID"
        }
    }

    public static func grouping(_ grouping: IssueGrouping) -> String {
        switch grouping {
        case .none: "No grouping"
        case .category: "Lifecycle"
        case .status: "Status"
        case .priority: "Priority"
        case .type: "Type"
        case .assignee: "Assignee"
        case .parent: "Parent"
        }
    }

    public static func field(_ field: FilterField) -> String {
        switch field {
        case .status: "Status"
        case .priority: "Priority"
        case .type: "Type"
        case .assignee: "Assignee"
        case .labels: "Labels"
        case .blocked: "Blocked"
        case .parent: "Parent epic"
        case .updated: "Updated"
        case .closed: "Closed"
        }
    }

    /// Plural noun for summaries like "3 labels".
    static func noun(_ field: FilterField) -> String {
        switch field {
        case .status: "statuses"
        case .priority: "priorities"
        case .type: "types"
        case .assignee: "assignees"
        case .labels: "labels"
        case .blocked: "values"
        case .parent: "epics"
        case .updated, .closed: "windows"
        }
    }

    /// How an operator reads in a chip, given how many values the rule has. Menus use the
    /// several-values form.
    public static func operatorTitle(_ op: FilterOperator, valueCount: Int, field: FilterField) -> String {
        if field == .blocked {
            return op == .isNoneOf ? "no" : "yes"
        }
        let one = valueCount <= 1
        switch op {
        case .isAnyOf: return one ? "is" : "is any of"
        case .isNoneOf: return one ? "is not" : "is none of"
        case .includesAll: return one ? "includes" : "include all of"
        case .includesAny: return one ? "includes" : "include any of"
        case .includesNone: return one ? "doesn't include" : "include none of"
        case .within: return "within the last"
        }
    }
}
