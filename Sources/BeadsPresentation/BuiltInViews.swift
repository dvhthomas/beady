import BeadsCore

public extension IssueView.ID {
    static let frontier: Self = "frontier"
    static let inFlight: Self = "inFlight"
    static let stuck: Self = "stuck"
    static let pipeline: Self = "pipeline"
    static let recent: Self = "recent"
    static let landed: Self = "landed"
    static let deferred: Self = "deferred"
    static let everything: Self = "everything"
    static let starred: Self = "starred"
}

public extension IssueView {
    /// Shipped with Beady, in sidebar order. Names say what the view answers, not which bd
    /// status it is; the palette answers to both. Open and Closed are one Lifecycle chip away
    /// from Everything and Landed, so they aren't rows of their own.
    static let builtIns: [IssueView] = [
        builtIn(.frontier, "Frontier", ViewIcon.builtIn[.frontier]!,
                rules: [FilterRule(field: .ready, op: .isAnyOf, values: [FilterRule.readyValue])],
                ViewPresentation(layout: .list, grouping: .none, ordering: .priority)),
        builtIn(.inFlight, "In Flight", ViewIcon.builtIn[.inFlight]!,
                rules: [FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.wip.rawValue])],
                ViewPresentation(layout: .list, grouping: .status, ordering: .recentlyUpdated)),
        builtIn(.stuck, "Stuck", ViewIcon.builtIn[.stuck]!,
                rules: [FilterRule(field: .blocked, op: .isAnyOf, values: [FilterRule.blockedValue])],
                // Blockers matter here and nowhere much else, so the Blocked-by column is on.
                ViewPresentation(layout: .list, grouping: .none, ordering: .priority,
                                 columns: ListColumn.allCases.filter { $0.isVisibleByDefault || $0 == .blockedBy }.map(\.id))),
        builtIn(.pipeline, "Pipeline", ViewIcon.builtIn[.pipeline]!,
                // Everything live, plus a week of what landed: a working board, not an archive.
                rules: [FilterRule(field: .closed, op: .within, values: [TimeWindow.week.rawValue])],
                ViewPresentation(layout: .board, grouping: .category, ordering: .priority)),
        builtIn(.recent, "Recent", ViewIcon.builtIn[.recent]!,
                rules: [FilterRule(field: .updated, op: .within, values: [TimeWindow.day.rawValue])],
                ViewPresentation(layout: .list, grouping: .assignee, ordering: .recentlyUpdated)),
        builtIn(.landed, "Landed", ViewIcon.builtIn[.landed]!,
                rules: [
                    FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.done.rawValue]),
                    FilterRule(field: .closed, op: .within, values: [TimeWindow.week.rawValue]),
                ],
                ViewPresentation(layout: .list, grouping: .none, ordering: .recentlyClosed)),
        builtIn(.deferred, "Deferred", ViewIcon.builtIn[.deferred]!,
                rules: [FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.frozen.rawValue])],
                ViewPresentation(layout: .list, grouping: .none, ordering: .priority)),
        builtIn(.everything, "Everything", ViewIcon.builtIn[.everything]!,
                rules: [],
                ViewPresentation(layout: .list, grouping: .category, ordering: .recentlyUpdated)),
        builtIn(.starred, "Starred", ViewIcon.builtIn[.starred]!,
                rules: [FilterRule(field: .labels, op: .includesAll, values: [IssueMark.starred.label])],
                // A label spans every lifecycle, so lifecycle is the grouping that reads best.
                ViewPresentation(layout: .list, grouping: .category, ordering: .priority)),
    ]

    static func builtIn(_ id: ID) -> IssueView? {
        builtIns.first { $0.id == id }
    }

    private static func builtIn(_ id: ID, _ name: String, _ symbol: String, rules: [FilterRule], _ presentation: ViewPresentation) -> IssueView {
        IssueView(id: id, name: name, symbol: symbol, filter: ViewFilter(rules: rules), presentation: presentation, isBuiltIn: true)
    }
}
