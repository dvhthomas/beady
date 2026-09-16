import BeadsCore

// BeadsPresentation: UI-framework-free view state. Views bind to these types;
// everything that decides what is shown is tested here, not in SwiftUI.

public enum DisplayText {
    /// The full text of a cell for a hover preview, or nil when there's nothing to show.
    /// Long text is cut at `limit` characters — at a word boundary where one is close — and
    /// ends in an ellipsis so it's clear there is more.
    public static func preview(_ text: String, limit: Int = 512) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        var cut = String(trimmed.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: space, to: cut.endIndex) < 24 {
            cut = String(cut[cut.startIndex..<space])
        }
        return cut + "…"
    }

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

    public static func layout(_ layout: WorkspaceModel.Layout) -> String {
        switch layout {
        case .list: "List"
        case .board: "Board"
        case .tree: "Tree"
        }
    }

    /// The SF Symbol for a layout, used by the header switcher and the Display picker.
    public static func layoutSymbol(_ layout: WorkspaceModel.Layout) -> String {
        switch layout {
        case .list: "list.bullet"
        case .board: "rectangle.split.3x1"
        case .tree: "list.bullet.indent"
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
