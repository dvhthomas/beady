import BeadsCore
import Foundation

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
        case .day: String(localized: "24 hours", bundle: .module, comment: "A time window, as a filter value")
        case .week: String(localized: "7 days", bundle: .module, comment: "A time window, as a filter value")
        case .month: String(localized: "30 days", bundle: .module, comment: "A time window, as a filter value")
        case .quarter: String(localized: "90 days", bundle: .module, comment: "A time window, as a filter value")
        }
    }

    public static func category(_ category: StatusCategory) -> String {
        switch category {
        case .active: String(localized: "Open", bundle: .module, comment: "Lifecycle category name, as a group header")
        case .wip: String(localized: "In Flight", bundle: .module, comment: "Lifecycle category name, as a group header: work in progress")
        case .frozen: String(localized: "Deferred", bundle: .module, comment: "Lifecycle category name, as a group header")
        case .done: String(localized: "Closed", bundle: .module, comment: "Lifecycle category name, as a group header")
        }
    }

    /// A category as a Lifecycle filter value, in bd's own words, so it isn't mistaken for the
    /// status of the same name: "Lifecycle · is · Active" rather than "Open".
    public static func lifecycle(_ category: StatusCategory) -> String {
        switch category {
        case .active: String(localized: "Active", bundle: .module, comment: "Lifecycle filter value, bd's own word")
        case .wip: String(localized: "In Flight", bundle: .module, comment: "Lifecycle filter value: work in progress")
        case .frozen: String(localized: "Frozen", bundle: .module, comment: "Lifecycle filter value, bd's own word")
        case .done: String(localized: "Done", bundle: .module, comment: "Lifecycle filter value, bd's own word")
        }
    }

    public static func sort(_ sort: IssueSort) -> String {
        switch sort {
        case .priority: String(localized: "Priority", bundle: .module, comment: "An ordering")
        case .recentlyUpdated: String(localized: "Last updated", bundle: .module, comment: "An ordering")
        case .recentlyCreated: String(localized: "Last created", bundle: .module, comment: "An ordering")
        case .recentlyClosed: String(localized: "Last closed", bundle: .module, comment: "An ordering")
        case .issueID: String(localized: "ID", bundle: .module, comment: "An ordering: by bead id")
        }
    }

    public static func layout(_ layout: WorkspaceModel.Layout) -> String {
        switch layout {
        case .list: String(localized: "List", bundle: .module, comment: "A layout")
        case .board: String(localized: "Board", bundle: .module, comment: "A layout: kanban columns")
        case .tree: String(localized: "Tree", bundle: .module, comment: "A layout: parent/child outline")
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
        case .none: String(localized: "No grouping", bundle: .module)
        case .category: String(localized: "Lifecycle", bundle: .module, comment: "A grouping: by bd's lifecycle category")
        case .status: String(localized: "Status", bundle: .module, comment: "A grouping")
        case .priority: String(localized: "Priority", bundle: .module, comment: "A grouping")
        case .type: String(localized: "Type", bundle: .module, comment: "A grouping: by bead type")
        case .assignee: String(localized: "Assignee", bundle: .module, comment: "A grouping")
        case .parent: String(localized: "Parent", bundle: .module, comment: "A grouping: by parent bead")
        }
    }

    /// The details pane with nothing selected. When there is history behind it, the Back and
    /// Forward arrows are the only other thing in the pane, so the text says what they do.
    public static func noSelection(canGoBack: Bool, canGoForward: Bool) -> String {
        switch (canGoBack, canGoForward) {
        case (true, true):
            String(localized: "Select a bead to see its details, or step back (⌘[) or forward (⌘]) through the ones you looked at.", bundle: .module)
        case (true, false):
            String(localized: "Select a bead to see its details, or go back to the last one you looked at (⌘[).", bundle: .module)
        case (false, true):
            String(localized: "Select a bead to see its details, or go forward to the one you came back from (⌘]).", bundle: .module)
        case (false, false):
            String(localized: "Select a bead to see its details.", bundle: .module)
        }
    }

    public static func field(_ field: FilterField) -> String {
        switch field {
        case .lifecycle: String(localized: "Lifecycle", bundle: .module, comment: "A filter field")
        case .status: String(localized: "Status", bundle: .module, comment: "A filter field")
        case .priority: String(localized: "Priority", bundle: .module, comment: "A filter field")
        case .type: String(localized: "Type", bundle: .module, comment: "A filter field: bead type")
        case .assignee: String(localized: "Assignee", bundle: .module, comment: "A filter field")
        case .labels: String(localized: "Labels", bundle: .module, comment: "A filter field")
        case .blocked: String(localized: "Blocked", bundle: .module, comment: "A filter field: whether something upstream blocks the bead")
        case .ready: String(localized: "Ready", bundle: .module, comment: "A filter field: whether bd lists the bead as ready")
        case .parent: String(localized: "Parent epic", bundle: .module, comment: "A filter field")
        case .updated: String(localized: "Updated", bundle: .module, comment: "A filter field: when the bead last changed")
        case .closed: String(localized: "Closed", bundle: .module, comment: "A filter field: when the bead was closed")
        }
    }

    /// Plural noun for summaries like "3 labels".
    static func noun(_ field: FilterField) -> String {
        switch field {
        case .lifecycle: String(localized: "categories", bundle: .module, comment: "Plural noun in a chip such as ‘3 categories’")
        case .status: String(localized: "statuses", bundle: .module, comment: "Plural noun in a chip such as ‘3 statuses’")
        case .priority: String(localized: "priorities", bundle: .module, comment: "Plural noun in a chip such as ‘3 priorities’")
        case .type: String(localized: "types", bundle: .module, comment: "Plural noun in a chip such as ‘3 types’")
        case .assignee: String(localized: "assignees", bundle: .module, comment: "Plural noun in a chip such as ‘3 assignees’")
        case .labels: String(localized: "labels", bundle: .module, comment: "Plural noun in a chip such as ‘3 labels’")
        case .blocked, .ready: String(localized: "values", bundle: .module, comment: "Plural noun in a chip such as ‘3 values’")
        case .parent: String(localized: "epics", bundle: .module, comment: "Plural noun in a chip such as ‘3 epics’")
        case .updated, .closed: String(localized: "windows", bundle: .module, comment: "Plural noun in a chip such as ‘3 windows’ (time windows)")
        }
    }

    /// How an operator reads in a chip, given how many values the rule has. Menus use the
    /// several-values form.
    public static func operatorTitle(_ op: FilterOperator, valueCount: Int, field: FilterField) -> String {
        if field == .blocked {
            return op == .isNoneOf
                ? String(localized: "no", bundle: .module, comment: "Filter operator for Blocked: ‘Blocked · no’")
                : String(localized: "yes", bundle: .module, comment: "Filter operator for Blocked: ‘Blocked · yes’")
        }
        let one = valueCount <= 1
        switch op {
        case .isAnyOf: return one
            ? String(localized: "is", bundle: .module, comment: "Filter operator in a chip: ‘Priority · is · P1’")
            : String(localized: "is any of", bundle: .module, comment: "Filter operator in a chip: ‘Priority · is any of · P1, P2’")
        case .isNoneOf: return one
            ? String(localized: "is not", bundle: .module, comment: "Filter operator in a chip: ‘Priority · is not · P1’")
            : String(localized: "is none of", bundle: .module, comment: "Filter operator in a chip: ‘Priority · is none of · P1, P2’")
        case .includesAll: return one
            ? String(localized: "includes", bundle: .module, comment: "Filter operator in a chip: ‘Labels · includes · ui’")
            : String(localized: "include all of", bundle: .module, comment: "Filter operator in a chip: ‘Labels · include all of · ui, api’")
        case .includesAny: return one
            ? String(localized: "includes", bundle: .module, comment: "Filter operator in a chip: ‘Labels · includes · ui’")
            : String(localized: "include any of", bundle: .module, comment: "Filter operator in a chip: ‘Labels · include any of · ui, api’")
        case .includesNone: return one
            ? String(localized: "doesn't include", bundle: .module, comment: "Filter operator in a chip: ‘Labels · doesn't include · ui’")
            : String(localized: "include none of", bundle: .module, comment: "Filter operator in a chip: ‘Labels · include none of · ui, api’")
        case .within: return String(localized: "within the last", bundle: .module, comment: "Filter operator in a chip: ‘Updated · within the last · 7 days’")
        }
    }
}

// MARK: Hover help

// Ready, Blocked, Deferred, Pinned, Hooked and the lifecycle categories are not plain English:
// each means something exact in bd. These are the one-sentence definitions the UI shows on hover,
// phrased from bd's own words (`bd statuses`, `bd ready --help`). Views read them from the
// presentation models or call these directly; they never spell them out themselves.
extension DisplayText {
    /// What a built-in view shows, in bd's words; empty for a user view, whose name is its own.
    public static func help(forView id: IssueView.ID) -> String {
        switch id {
        case .frontier:
            String(localized: "bd's ready work: active, with nothing open blocking it in the dependency graph, not deferred to a future date and not hooked or held by a gate; computed, not a stored status.", bundle: .module, comment: "Hover help for the Ready view")
        case .inFlight:
            String(localized: "Beads in bd's wip category: in_progress, blocked and hooked, plus any custom status filed under wip.", bundle: .module, comment: "Hover help for the In Flight view")
        case .stuck:
            String(localized: "Beads with an open blocker upstream, computed from the dependency graph rather than read from the stored blocked status.", bundle: .module, comment: "Hover help for the Stuck view")
        case .pipeline:
            String(localized: "Every live bead on a board of bd's lifecycle categories, with the done column kept to the last 7 days so it stays a working surface.", bundle: .module, comment: "Hover help for the Pipeline view")
        case .recent:
            String(localized: "Beads bd changed in the last 24 hours, whatever their status, grouped by who holds them.", bundle: .module, comment: "Hover help for the Recent view")
        case .landed:
            String(localized: "Beads in bd's done category (closed, plus any custom status filed under done) that were closed in the last 7 days.", bundle: .module, comment: "Hover help for the Landed view")
        case .deferred:
            String(localized: "Beads in bd's frozen category: deferred (put on ice until a date or forever) and pinned (stays open indefinitely).", bundle: .module, comment: "Hover help for the Deferred view")
        case .everything:
            String(localized: "Every bead in the database, whatever its status.", bundle: .module, comment: "Hover help for the Everything view")
        case .starred:
            String(localized: "Beads carrying the starred label, whatever their status.", bundle: .module, comment: "Hover help for the Starred view")
        default:
            ""
        }
    }

    public static func help(for category: StatusCategory) -> String {
        switch category {
        case .active:
            String(localized: "bd's active category: available to work, which is the open status unless this database adds its own.", bundle: .module, comment: "Hover help; keep bd's words active and open as they are")
        case .wip:
            String(localized: "bd's wip category: being worked on, which is in_progress, blocked and hooked unless this database adds its own.", bundle: .module, comment: "Hover help; keep bd's words wip, in_progress, blocked and hooked as they are")
        case .frozen:
            String(localized: "bd's frozen category: deliberately set aside, which is deferred and pinned unless this database adds its own.", bundle: .module, comment: "Hover help; keep bd's words frozen, deferred and pinned as they are")
        case .done:
            String(localized: "bd's done category: completed, which is closed unless this database adds its own.", bundle: .module, comment: "Hover help; keep bd's words done and closed as they are")
        }
    }

    /// A built-in status in bd's words; a custom one is explained through the category this
    /// database files it under.
    public static func help(forStatus status: String, category: StatusCategory) -> String {
        switch status {
        case "open":
            String(localized: "Available to work: bd's default status, in the active category.", bundle: .module, comment: "Hover help for bd's open status")
        case "in_progress":
            String(localized: "Actively being worked on; in the wip category.", bundle: .module, comment: "Hover help for bd's in_progress status")
        case "blocked":
            String(localized: "Blocked by a dependency as a stored status, in the wip category; the Blocked view and filter use the dependency graph instead, so a bead can be blocked without it.", bundle: .module, comment: "Hover help for bd's blocked status")
        case "hooked":
            String(localized: "Attached to an agent's hook, in the wip category, so bd ready leaves it alone.", bundle: .module, comment: "Hover help for bd's hooked status")
        case "deferred":
            String(localized: "Deliberately put on ice for later, until a defer date or indefinitely; in the frozen category.", bundle: .module, comment: "Hover help for bd's deferred status")
        case "pinned":
            String(localized: "Persistent and stays open indefinitely; in the frozen category.", bundle: .module, comment: "Hover help for bd's pinned status")
        case "closed":
            String(localized: "Completed; in the done category.", bundle: .module, comment: "Hover help for bd's closed status")
        default:
            String(localized: "A custom status this database files under \(category.rawValue): \(lowercasedFirst(help(for: category)))", bundle: .module, comment: "Hover help for a status bd doesn't ship with: bd's category name, then that category's definition")
        }
    }

    public static func help(for field: FilterField) -> String {
        switch field {
        case .lifecycle:
            String(localized: "bd's lifecycle category for the bead's status: active, wip, frozen or done.", bundle: .module, comment: "Hover help for a filter field")
        case .ready:
            String(localized: "Whether bd would list the bead as ready: active, nothing open blocking it, not deferred to a future date and not hooked; computed, not a stored status.", bundle: .module, comment: "Hover help for a filter field")
        case .status:
            String(localized: "The bead's stored bd status: open, in_progress, blocked, hooked, deferred, pinned, closed, or one this database adds.", bundle: .module, comment: "Hover help for a filter field")
        case .priority:
            String(localized: "bd's priority from P0 (critical) to P4 (backlog).", bundle: .module, comment: "Hover help for a filter field")
        case .type:
            String(localized: "The bead's type, such as task, bug, feature or epic.", bundle: .module, comment: "Hover help for a filter field")
        case .assignee:
            String(localized: "Who the bead is assigned to in bd, or no one.", bundle: .module, comment: "Hover help for a filter field")
        case .labels:
            String(localized: "The bead's labels; a bead can carry several.", bundle: .module, comment: "Hover help for a filter field")
        case .blocked:
            String(localized: "Whether an open bead upstream blocks this one, computed from the dependency graph rather than read from the stored blocked status.", bundle: .module, comment: "Hover help for a filter field")
        case .parent:
            String(localized: "The epic the bead sits under.", bundle: .module, comment: "Hover help for a filter field")
        case .updated:
            String(localized: "When bd last changed the bead, counted back from now.", bundle: .module, comment: "Hover help for a filter field")
        case .closed:
            String(localized: "When the bead was closed, counted back from now.", bundle: .module, comment: "Hover help for a filter field")
        }
    }

    /// The definition of a fixed filter value — a status, a time window, the blocked flag — or
    /// nil for a free-form value such as a name or a label, which has nothing to define.
    public static func help(forValue value: String, in field: FilterField, catalog: StatusCatalog = .builtIn) -> String? {
        switch field {
        case .lifecycle:
            StatusCategory(rawValue: value).map(help(for:))
        case .status:
            help(forStatus: value, category: catalog.category(of: value))
        case .blocked:
            value == FilterRule.blockedValue ? help(forView: .stuck) : nil
        case .ready:
            value == FilterRule.readyValue ? help(forView: .frontier) : nil
        case .updated, .closed:
            TimeWindow(rawValue: value).map { String(localized: "Within the last \(window($0)), counted back from now.", bundle: .module, comment: "Hover help for a time window such as ‘7 days’") }
        case .priority, .type, .assignee, .labels, .parent:
            nil
        }
    }

    public static func help(for grouping: IssueGrouping) -> String {
        switch grouping {
        case .none: String(localized: "One flat list in the chosen order.", bundle: .module, comment: "Hover help for a grouping")
        case .category: String(localized: "A section for each of bd's lifecycle categories: active, wip, frozen and done.", bundle: .module, comment: "Hover help for a grouping")
        case .status: String(localized: "A section for each stored bd status.", bundle: .module, comment: "Hover help for a grouping")
        case .priority: String(localized: "A section for each priority, P0 first.", bundle: .module, comment: "Hover help for a grouping")
        case .type: String(localized: "A section for each bead type.", bundle: .module, comment: "Hover help for a grouping")
        case .assignee: String(localized: "A section for each assignee, with unassigned beads together.", bundle: .module, comment: "Hover help for a grouping")
        case .parent: String(localized: "A section for each parent epic, with top-level beads together.", bundle: .module, comment: "Hover help for a grouping")
        }
    }

    private static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}
