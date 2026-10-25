import BeadsCore
import Foundation

public extension IssueView.ID {
    /// The Ready view. The id keeps the name it shipped under, so a remembered presentation or a
    /// .beadyview keyed by it still resolves after the rename.
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
        builtIn(.pipeline, String(localized: "Pipeline", bundle: .module, comment: "Built-in view: a board of everything live"), ViewIcon.builtIn[.pipeline]!,
                // First, as the working board: everything live, plus a week of what landed.
                rules: [FilterRule(field: .closed, op: .within, values: [TimeWindow.week.rawValue])],
                ViewPresentation(layout: .board, grouping: .category, ordering: .priority)),
        builtIn(.frontier, String(localized: "Ready", bundle: .module, comment: "Built-in view: bd's ready work"), ViewIcon.builtIn[.frontier]!,
                rules: [FilterRule(field: .ready, op: .isAnyOf, values: [FilterRule.readyValue])],
                ViewPresentation(layout: .list, grouping: .none, ordering: .priority)),
        builtIn(.inFlight, String(localized: "In Flight", bundle: .module, comment: "Built-in view: work in progress"), ViewIcon.builtIn[.inFlight]!,
                rules: [FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.wip.rawValue])],
                ViewPresentation(layout: .list, grouping: .status, ordering: .recentlyUpdated)),
        builtIn(.stuck, String(localized: "Stuck", bundle: .module, comment: "Built-in view: blocked by something upstream"), ViewIcon.builtIn[.stuck]!,
                rules: [FilterRule(field: .blocked, op: .isAnyOf, values: [FilterRule.blockedValue])],
                // Blockers matter here and nowhere much else, so the Blocked-by column is on.
                ViewPresentation(layout: .list, grouping: .none, ordering: .priority,
                                 columns: ListColumn.allCases.filter { $0.isVisibleByDefault || $0 == .blockedBy }.map(\.id))),
        builtIn(.recent,String(localized: "Recent", bundle: .module, comment: "Built-in view: changed in the last day"), ViewIcon.builtIn[.recent]!,
                rules: [FilterRule(field: .updated, op: .within, values: [TimeWindow.day.rawValue])],
                ViewPresentation(layout: .list, grouping: .assignee, ordering: .recentlyUpdated)),
        builtIn(.landed, String(localized: "Landed", bundle: .module, comment: "Built-in view: closed in the last week"), ViewIcon.builtIn[.landed]!,
                rules: [
                    FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.done.rawValue]),
                    FilterRule(field: .closed, op: .within, values: [TimeWindow.week.rawValue]),
                ],
                ViewPresentation(layout: .list, grouping: .none, ordering: .recentlyClosed)),
        builtIn(.deferred, String(localized: "Deferred", bundle: .module, comment: "Built-in view: bd's frozen category"), ViewIcon.builtIn[.deferred]!,
                rules: [FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.frozen.rawValue])],
                ViewPresentation(layout: .list, grouping: .none, ordering: .priority)),
        builtIn(.everything, String(localized: "Everything", bundle: .module, comment: "Built-in view: the whole database"), ViewIcon.builtIn[.everything]!,
                rules: [],
                ViewPresentation(layout: .list, grouping: .category, ordering: .recentlyUpdated)),
        builtIn(.starred, String(localized: "Starred", bundle: .module, comment: "Built-in view: starred beads"), ViewIcon.builtIn[.starred]!,
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
