import BeadsCore
import Foundation
import Testing

/// Shared data for the view-filter suites.
enum ViewFixture {
    static let now = t0 + days(30)
    static let snapshot = IssueSnapshot(issues: [
        makeIssue("epic", type: "epic", labels: ["plan"]),
        makeIssue("a", title: "Globe midpoint", priority: 1, type: "bug", assignee: "Ann",
                  labels: ["renderer", "print"], parent: "epic", updated: t0 + days(29)),
        makeIssue("b", title: "Print cover", status: "in_progress", priority: 2, type: "bug",
                  labels: ["renderer"], updated: t0 + days(29)),
        makeIssue("c", title: "Toolbar", status: "closed", priority: 3, type: "task", assignee: "Bo",
                  labels: ["print"], closed: t0 + days(27)),
        makeIssue("d", title: "Blocked thing", priority: 1, parent: "a", blockedBy: ["b"]),
    ])

    static func ids(_ filter: ViewFilter, in source: ViewSource = .lifecycle(.all)) -> Set<IssueID> {
        Set(snapshot.issues.filter {
            source.includes($0, in: snapshot, now: now) && filter.matches($0, in: snapshot, now: now)
        }.map(\.id))
    }

    static func rule(_ field: FilterField, _ op: FilterOperator, _ values: Set<String>) -> ViewFilter {
        ViewFilter(rules: [FilterRule(field: field, op: op, values: values)])
    }
}

@Suite("Filter rules match like Linear's operators")
struct FilterRuleMatchingTests {
    typealias F = ViewFixture

    @Test("is any of: single-valued fields match any chosen value")
    func isAnyOf() {
        #expect(F.ids(F.rule(.priority, .isAnyOf, ["1", "3"])) == ["a", "c", "d"])
        #expect(F.ids(F.rule(.type, .isAnyOf, ["bug"])) == ["a", "b"])
        #expect(F.ids(F.rule(.status, .isAnyOf, ["closed"])) == ["c"])
    }

    @Test("is none of excludes the chosen values")
    func isNoneOf() {
        #expect(F.ids(F.rule(.type, .isNoneOf, ["bug"])) == ["epic", "c", "d"])
        #expect(F.ids(F.rule(.assignee, .isNoneOf, [FilterRule.unassigned])) == ["a", "c"])
    }

    @Test("assignee can match Unassigned alongside people")
    func unassigned() {
        #expect(F.ids(F.rule(.assignee, .isAnyOf, [FilterRule.unassigned, "Bo"])) == ["epic", "b", "c", "d"])
    }

    @Test("labels: includes all of, any of, none of")
    func labels() {
        #expect(F.ids(F.rule(.labels, .includesAll, ["renderer", "print"])) == ["a"])
        #expect(F.ids(F.rule(.labels, .includesAny, ["renderer", "print"])) == ["a", "b", "c"])
        #expect(F.ids(F.rule(.labels, .includesNone, ["print"])) == ["epic", "b", "d"])
    }

    @Test("blocked is / is not uses dependency state")
    func blocked() {
        #expect(F.ids(F.rule(.blocked, .isAnyOf, [FilterRule.blockedValue])) == ["d"])
        #expect(F.ids(F.rule(.blocked, .isNoneOf, [FilterRule.blockedValue])) == ["epic", "a", "b", "c"])
    }

    @Test("parent epic matches anything under it, at any depth")
    func parent() {
        #expect(F.ids(F.rule(.parent, .isAnyOf, ["epic"])) == ["a", "d"])
        #expect(F.ids(F.rule(.parent, .isNoneOf, ["epic"])) == ["epic", "b", "c"])
    }

    @Test("dates match within the chosen window")
    func dates() {
        #expect(F.ids(F.rule(.updated, .within, [TimeWindow.day.rawValue])) == ["a", "b"])
        #expect(F.ids(F.rule(.closed, .within, [TimeWindow.week.rawValue])) == ["c"])
    }

    @Test("a rule with no values matches everything")
    func emptyRule() {
        #expect(F.ids(F.rule(.type, .isAnyOf, [])).count == 5)
    }

    @Test("rules are ANDed, and every search word must match")
    func combined() {
        var filter = ViewFilter(rules: [
            FilterRule(field: .type, op: .isAnyOf, values: ["bug"]),
            FilterRule(field: .priority, op: .isAnyOf, values: ["1"]),
        ])
        #expect(F.ids(filter) == ["a"])
        filter.searchText = "globe"
        #expect(F.ids(filter) == ["a"])
        filter.searchText = "globe cover"
        #expect(F.ids(filter).isEmpty)
    }
}

@Suite("Editing a view filter")
struct ViewFilterEditingTests {
    @Test("ticking adds a rule with the field's default operator; unticking the last value removes it")
    func tickAndUntick() {
        var filter = ViewFilter()
        filter.toggle("1", in: .priority)
        #expect(filter.rules == [FilterRule(field: .priority, op: .isAnyOf, values: ["1"])])
        filter.toggle("2", in: .priority)
        #expect(filter.rule(for: .priority)?.values == ["1", "2"])
        filter.toggle("1", in: .priority)
        filter.toggle("2", in: .priority)
        #expect(filter.rules.isEmpty)

        filter.toggle("print", in: .labels)
        #expect(filter.rule(for: .labels)?.op == .includesAll)
    }

    @Test("blocked and date fields hold one value at a time")
    func singleChoice() {
        var filter = ViewFilter()
        filter.toggle(TimeWindow.day.rawValue, in: .updated)
        filter.toggle(TimeWindow.week.rawValue, in: .updated)
        #expect(filter.rule(for: .updated)?.values == [TimeWindow.week.rawValue])
        filter.toggle(TimeWindow.week.rawValue, in: .updated)
        #expect(filter.rule(for: .updated) == nil)
    }

    @Test("operators can only be switched to ones that fit the field")
    func operators() {
        #expect(FilterField.type.operators == [.isAnyOf, .isNoneOf])
        #expect(FilterField.labels.operators == [.includesAll, .includesAny, .includesNone])
        #expect(FilterField.updated.operators == [.within])
        #expect(FilterField.blocked.operators == [.isAnyOf, .isNoneOf])

        var filter = ViewFilter()
        filter.toggle("bug", in: .type)
        filter.setOperator(.isNoneOf, for: .type)
        #expect(filter.rule(for: .type)?.op == .isNoneOf)
        filter.setOperator(.includesAll, for: .type)
        #expect(filter.rule(for: .type)?.op == .isNoneOf)
    }

    @Test("one rule per field, kept in the order they were added")
    func order() {
        var filter = ViewFilter()
        filter.toggle("bug", in: .type)
        filter.toggle("1", in: .priority)
        filter.toggle("task", in: .type)
        #expect(filter.rules.map(\.field) == [.type, .priority])
        filter.remove(.type)
        #expect(filter.rules.map(\.field) == [.priority])
    }

    @Test("clearing rules keeps the search; a filter is empty only with no rules and no search words")
    func clearing() {
        var filter = ViewFilter()
        filter.toggle("bug", in: .type)
        filter.searchText = "globe"
        filter.removeAllRules()
        #expect(filter.rules.isEmpty)
        #expect(filter.searchText == "globe")
        #expect(!filter.isEmpty)
        filter.searchText = "   "
        #expect(filter.isEmpty)
    }
}

@Suite("View sources")
struct ViewSourceTests {
    typealias F = ViewFixture

    @Test("a lifecycle source is its scope")
    func lifecycle() {
        #expect(F.ids(ViewFilter(), in: .lifecycle(.inFlight)) == ["b"])
        #expect(F.ids(ViewFilter(), in: .lifecycle(.closed)) == ["c"])
        #expect(F.ids(ViewFilter(), in: .lifecycle(.blocked)) == ["d"])
    }

    @Test("an epic source is everything under the epic, whatever its status, not the epic itself")
    func epic() {
        #expect(F.ids(ViewFilter(), in: .focused("epic")) == ["a", "d"])
    }

    @Test("each source knows which status categories can appear in it")
    func categories() {
        #expect(ViewSource.lifecycle(.open).categories == [.active])
        #expect(ViewSource.lifecycle(.ready).categories == [.active])
        #expect(ViewSource.lifecycle(.inFlight).categories == [.wip])
        #expect(ViewSource.lifecycle(.deferred).categories == [.frozen])
        #expect(ViewSource.lifecycle(.closed).categories == [.done])
        #expect(ViewSource.lifecycle(.blocked).categories == [.active, .wip, .frozen])
        #expect(ViewSource.lifecycle(.all).categories == Set(StatusCategory.allCases))
        #expect(ViewSource.focused("epic").categories == Set(StatusCategory.allCases))
    }
}

@Suite("Filter options and counts")
struct FilterOptionsTests {
    typealias F = ViewFixture

    func options(_ field: FilterField, in source: ViewSource = .lifecycle(.all), filter: ViewFilter = ViewFilter()) -> [String] {
        FilterOptions.options(for: field, source: source, filter: filter, in: F.snapshot, now: F.now)
            .map { "\($0.isSelected ? "[x]" : "[ ]") \($0.value.isEmpty ? "∅" : $0.value) \($0.count)" }
    }

    @Test("status options are only the statuses the view can contain, in lifecycle order")
    func statusLimitedToView() {
        #expect(options(.status, in: .lifecycle(.inFlight)) == ["[ ] in_progress 1"])
        #expect(options(.status) == ["[ ] open 3", "[ ] in_progress 1", "[ ] closed 1"])
    }

    @Test("counts ignore the field's own rule but respect the others, so adding a second value is informed")
    func countsExcludeOwnRule() {
        var filter = ViewFilter()
        filter.toggle("1", in: .priority)
        filter.toggle("bug", in: .type)
        #expect(options(.priority, filter: filter) == ["[ ] 0 0", "[x] 1 1", "[ ] 2 1", "[ ] 3 0", "[ ] 4 0"])
    }

    @Test("long lists hide values with nothing in the view unless ticked")
    func hidingEmptyValues() {
        #expect(options(.type, in: .lifecycle(.inFlight)) == ["[ ] bug 1"])
        var filter = ViewFilter()
        filter.toggle("epic", in: .type)
        #expect(options(.type, in: .lifecycle(.inFlight), filter: filter) == ["[ ] bug 1", "[x] epic 0"])
    }

    @Test("assignee options put Unassigned first")
    func assignees() {
        #expect(options(.assignee) == ["[ ] ∅ 3", "[ ] Ann 1", "[ ] Bo 1"])
    }

    @Test("date options count the issues in each window")
    func dates() {
        #expect(options(.updated) == ["[ ] day 2", "[ ] week 2", "[ ] month 5", "[ ] quarter 5"])
        #expect(options(.closed) == ["[ ] day 0", "[ ] week 1", "[ ] month 1", "[ ] quarter 1"])
    }

    @Test("parent options are any unfinished bead holding work, not only epics; blocked is a single option")
    func parentAndBlocked() {
        // "a" is an ordinary task with a child, and belongs here just as much as the epic does.
        #expect(options(.parent) == ["[ ] a 1", "[ ] epic 2"])
        #expect(options(.blocked) == ["[ ] blocked 1"])
    }
}

@Suite("Grouping")
struct IssueGroupingTests {
    typealias F = ViewFixture

    func keys(_ grouping: IssueGrouping, including: [String] = []) -> [String] {
        grouping.groups(F.snapshot.issues, in: F.snapshot, including: including).map(\.key)
    }

    @Test("status groups follow the lifecycle, and keep each group's issues in the given order")
    func status() {
        let groups = IssueGrouping.status.groups(F.snapshot.issues, in: F.snapshot)
        #expect(groups.map(\.key) == ["open", "in_progress", "closed"])
        #expect(groups[0].issues.map(\.id) == ["a", "d", "epic"])
    }

    @Test("lifecycle groups use bd's categories")
    func category() {
        #expect(keys(.category) == ["active", "wip", "done"])
    }

    @Test("priority groups are numeric, and requested empty groups are included in order")
    func priority() {
        #expect(keys(.priority) == ["1", "2", "3"])
        #expect(keys(.priority, including: ["0", "4"]) == ["0", "1", "2", "3", "4"])
    }

    @Test("assignee and parent groups put Unassigned and No parent last")
    func assigneeAndParent() {
        #expect(keys(.assignee) == ["Ann", "Bo", ""])
        #expect(keys(.parent) == ["a", "epic", ""])
    }

    @Test("no grouping is a single group of everything")
    func none() {
        let groups = IssueGrouping.none.groups(F.snapshot.issues, in: F.snapshot)
        #expect(groups.map(\.key) == [""])
        #expect(groups.first?.issues.count == 5)
        #expect(IssueGrouping.none.groups([], in: F.snapshot).isEmpty)
    }
}
