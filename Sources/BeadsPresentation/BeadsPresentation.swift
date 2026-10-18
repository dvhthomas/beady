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

// MARK: Hover help

// Ready, Blocked, Deferred, Pinned, Hooked and the lifecycle categories are not plain English:
// each means something exact in bd. These are the one-sentence definitions the UI shows on hover,
// phrased from bd's own words (`bd statuses`, `bd ready --help`). Views read them from the
// presentation models or call these directly; they never spell them out themselves.
extension DisplayText {
    public static func help(for scope: Scope) -> String {
        switch scope {
        case .all:
            "Every bead in the database, whatever its status."
        case .open:
            "Beads in bd's active category (open, plus any custom status filed under active), blocked or not."
        case .ready:
            "bd's ready work: active, with nothing open blocking it in the dependency graph, not deferred to a future date and not hooked or held by a gate; computed, not a stored status."
        case .inFlight:
            "Beads in bd's wip category: in_progress, blocked and hooked, plus any custom status filed under wip."
        case .blocked:
            "Beads with an open blocker upstream, computed from the dependency graph rather than read from the stored blocked status."
        case .deferred:
            "Beads in bd's frozen category: deferred (put on ice until a date or forever) and pinned (stays open indefinitely)."
        case .closed:
            "Beads in bd's done category: closed, plus any custom status filed under done."
        }
    }

    public static func help(for category: StatusCategory) -> String {
        switch category {
        case .active:
            "bd's active category: available to work, which is the open status unless this database adds its own."
        case .wip:
            "bd's wip category: being worked on, which is in_progress, blocked and hooked unless this database adds its own."
        case .frozen:
            "bd's frozen category: deliberately set aside, which is deferred and pinned unless this database adds its own."
        case .done:
            "bd's done category: completed, which is closed unless this database adds its own."
        }
    }

    /// A built-in status in bd's words; a custom one is explained through the category this
    /// database files it under.
    public static func help(forStatus status: String, category: StatusCategory) -> String {
        switch status {
        case "open":
            "Available to work: bd's default status, in the active category."
        case "in_progress":
            "Actively being worked on; in the wip category."
        case "blocked":
            "Blocked by a dependency as a stored status, in the wip category; the Blocked view and filter use the dependency graph instead, so a bead can be blocked without it."
        case "hooked":
            "Attached to an agent's hook, in the wip category, so bd ready leaves it alone."
        case "deferred":
            "Deliberately put on ice for later, until a defer date or indefinitely; in the frozen category."
        case "pinned":
            "Persistent and stays open indefinitely; in the frozen category."
        case "closed":
            "Completed; in the done category."
        default:
            "A custom status this database files under \(category.rawValue): \(lowercasedFirst(help(for: category)))"
        }
    }

    public static func help(for field: FilterField) -> String {
        switch field {
        case .status:
            "The bead's stored bd status: open, in_progress, blocked, hooked, deferred, pinned, closed, or one this database adds."
        case .priority:
            "bd's priority from P0 (critical) to P4 (backlog)."
        case .type:
            "The bead's type, such as task, bug, feature or epic."
        case .assignee:
            "Who the bead is assigned to in bd, or no one."
        case .labels:
            "The bead's labels; a bead can carry several."
        case .blocked:
            "Whether an open bead upstream blocks this one, computed from the dependency graph rather than read from the stored blocked status."
        case .parent:
            "The epic the bead sits under."
        case .updated:
            "When bd last changed the bead, counted back from now."
        case .closed:
            "When the bead was closed, counted back from now."
        }
    }

    /// The definition of a fixed filter value — a status, a time window, the blocked flag — or
    /// nil for a free-form value such as a name or a label, which has nothing to define.
    public static func help(forValue value: String, in field: FilterField, catalog: StatusCatalog = .builtIn) -> String? {
        switch field {
        case .status:
            help(forStatus: value, category: catalog.category(of: value))
        case .blocked:
            value == FilterRule.blockedValue ? help(for: Scope.blocked) : nil
        case .updated, .closed:
            TimeWindow(rawValue: value).map { "Within the last \(window($0)), counted back from now." }
        case .priority, .type, .assignee, .labels, .parent:
            nil
        }
    }

    public static func help(for grouping: IssueGrouping) -> String {
        switch grouping {
        case .none: "One flat list in the chosen order."
        case .category: "A section for each of bd's lifecycle categories: active, wip, frozen and done."
        case .status: "A section for each stored bd status."
        case .priority: "A section for each priority, P0 first."
        case .type: "A section for each bead type."
        case .assignee: "A section for each assignee, with unassigned beads together."
        case .parent: "A section for each parent epic, with top-level beads together."
        }
    }

    private static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}
