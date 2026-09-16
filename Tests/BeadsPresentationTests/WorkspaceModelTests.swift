import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("WorkspaceModel loading")
struct WorkspaceModelLoadingTests {
    @Test("a successful load exposes the snapshot")
    func loads() async {
        let model = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a")]), now: { t0 })
        #expect(model.loadState == .idle)
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.snapshot?.issues.count == 1)
        #expect(model.lastLoaded == t0)
    }

    @Test("a first load that fails shows the error")
    func firstLoadFails() async {
        let model = WorkspaceModel(title: "demo", store: StubStore([.failure(LoadFailure())]))
        await model.load()
        #expect(model.loadState == .failed("bd exploded"))
        #expect(model.snapshot == nil)
    }

    @Test("a later failure keeps the last good data and reports the problem")
    func refreshFailureKeepsData() async {
        let store = StubStore([.success(IssueSnapshot(issues: [makeIssue("a")])), .failure(LoadFailure())])
        let model = WorkspaceModel(title: "demo", store: store)
        await model.load()
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.snapshot?.issues.count == 1)
        #expect(model.refreshError == "bd exploded")
    }

    @Test("refreshIfChanged reloads only when the store's change token moves")
    func changeDriven() async {
        let store = StubStore([makeIssue("a")])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        await model.refreshIfChanged()
        #expect(store.calls == 1)
        store.setToken("v2")
        await model.refreshIfChanged()
        #expect(store.calls == 2)
    }

    @Test("a write that lands mid-load triggers the next refresh")
    func writeDuringLoad() async {
        let store = StubStore([makeIssue("a")])
        store.onLoad = { $0.setToken("v2") }
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        await model.refreshIfChanged()
        #expect(store.calls == 2)
    }

    @Test("a failed load isn't retried on every poll")
    func failureNotHammered() async {
        let store = StubStore([.failure(LoadFailure())])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        await model.refreshIfChanged()
        await model.refreshIfChanged()
        #expect(store.calls == 1)
    }

    @Test("refreshIfChanged also reloads stale data, for writes it can't see")
    func staleReload() async {
        let store = StubStore([makeIssue("a")])
        let clock = Mutable(t0)
        let model = WorkspaceModel(title: "demo", store: store, now: { clock.value }, staleAfter: 300)
        await model.load()
        clock.value = t0 + 299
        await model.refreshIfChanged()
        #expect(store.calls == 1)
        clock.value = t0 + 301
        await model.refreshIfChanged()
        #expect(store.calls == 2)
    }
}

@MainActor
@Suite("Views keep their own filters and display, like Linear")
struct WorkspaceViewStateTests {
    let issues = [
        makeIssue("epic", type: "epic", labels: ["plan"]),
        makeIssue("epic.1", status: "in_progress", priority: 1, labels: ["plan", "ui"], parent: "epic", updated: t0 + 10),
        makeIssue("epic.2", status: "blocked", priority: 0, labels: ["ui"], parent: "epic", updated: t0 + 20),
        makeIssue("done-old", status: "closed", labels: ["ui"], closed: t0 + 5),
        makeIssue("done-new", status: "closed", priority: 0, closed: t0 + 50),
        makeIssue("todo", priority: 1, assignee: "Ann", labels: ["ui"]),
    ]

    func loadedModel() async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore(issues), now: { t0 + 100 })
        await model.load()
        return model
    }

    func chipText(_ model: WorkspaceModel) -> [String] {
        model.filterChips.map { "\($0.fieldTitle) | \($0.operatorTitle) | \($0.valuesTitle)" }
    }

    @Test("a status picked in Open doesn't leak into In Flight, and is still there back in Open")
    func filtersArePerView() async {
        let model = await loadedModel()
        #expect(model.source == .lifecycle(.open))
        model.toggleFilterValue("open", in: .status)
        #expect(model.visibleIssues.map(\.id) == ["todo", "epic"])

        model.source = .lifecycle(.inFlight)
        #expect(model.filter.isEmpty)
        #expect(Set(model.visibleIssues.map(\.id)) == ["epic.1", "epic.2"])

        model.source = .lifecycle(.open)
        #expect(model.filter.rule(for: .status)?.values == ["open"])
    }

    @Test("layout, grouping, ordering and search are per view too")
    func displayIsPerView() async {
        let model = await loadedModel()
        model.layout = .board
        model.grouping = .priority
        model.ordering = .issueID
        model.searchText = "todo"
        #expect(model.visibleIssues.map(\.id) == ["todo"])

        model.source = .lifecycle(.inFlight)
        #expect(model.layout == .list)
        #expect(model.grouping == .status)
        #expect(model.ordering == .recentlyUpdated)
        #expect(model.searchText == "")

        model.source = .lifecycle(.open)
        #expect(model.layout == .board)
        #expect(model.grouping == .priority)
        #expect(model.ordering == .issueID)
        #expect(model.searchText == "todo")
    }

    @Test("each kind of view starts with sensible display defaults")
    func defaults() async {
        let model = await loadedModel()
        #expect(model.grouping == .none)
        #expect(model.ordering == .priority)
        model.source = .lifecycle(.closed)
        #expect(model.ordering == .recentlyClosed)
        model.source = .lifecycle(.all)
        #expect(model.grouping == .category)
        #expect(model.ordering == .recentlyUpdated)
        model.source = .focused("epic")
        #expect(model.layout == .tree)
    }

    @Test("the status filter only offers statuses the view can contain")
    func statusOptionsFollowView() async {
        let model = await loadedModel()
        model.source = .lifecycle(.inFlight)
        #expect(model.filterOptions(for: .status).map { "\($0.title) \($0.count)" } == ["Blocked 1", "In Progress 1"])
        model.source = .lifecycle(.closed)
        #expect(model.filterOptions(for: .status).map(\.title) == ["Closed"])
    }

    @Test("sidebar counts are each view's total, whatever the filters")
    func sidebarCounts() async {
        let model = await loadedModel()
        let expected = ["Open 2", "Ready 2", "In Flight 2", "Blocked 1", "Deferred 0", "Closed 2", "All 6"]
        #expect(model.sidebarViews.map { "\($0.title) \($0.count)" } == expected)
        model.toggleFilterValue("ui", in: .labels)
        #expect(model.sidebarViews.map { "\($0.title) \($0.count)" } == expected)
    }

    @Test("a focused view shows everything under one bead, with filters of its own")
    func epicView() async {
        let model = await loadedModel()
        model.toggleFilterValue("ui", in: .labels)
        model.source = .focused("epic")
        #expect(model.filter.isEmpty)
        #expect(Set(model.visibleIssues.map(\.id)) == ["epic.1", "epic.2"])
        #expect(model.viewTitle == "Issue epic")
        model.source = .lifecycle(.inFlight)
        #expect(model.viewTitle == "In Flight")
    }

    @Test("chips read like Linear's: field, operator, values")
    func chips() async {
        let model = await loadedModel()
        model.source = .lifecycle(.all)
        model.toggleFilterValue("1", in: .priority)
        #expect(chipText(model) == ["Priority | is | P1"])
        model.toggleFilterValue("0", in: .priority)
        #expect(chipText(model) == ["Priority | is any of | P0, P1"])
        model.setFilterOperator(.isNoneOf, for: .priority)
        #expect(chipText(model) == ["Priority | is none of | P0, P1"])

        model.toggleFilterValue("plan", in: .labels)
        model.setFilterOperator(.includesNone, for: .labels)
        #expect(chipText(model).last == "Labels | doesn't include | plan")
        model.toggleFilterValue("ui", in: .labels)
        model.toggleFilterValue("x", in: .labels)
        #expect(chipText(model).last == "Labels | include none of | 3 labels")
        #expect(model.filterChips.last?.operators.map(\.title) == ["include all of", "include any of", "include none of"])
        #expect(model.filterChips.last?.operators.map(\.isSelected) == [false, false, true])

        model.removeFilter(.priority)
        #expect(model.filterChips.map(\.field) == [.labels])
    }

    @Test("filter menu options have readable titles and counts")
    func optionTitles() async {
        let model = await loadedModel()
        model.source = .lifecycle(.all)
        #expect(model.filterOptions(for: .assignee).map { "\($0.title) \($0.count)" } == ["Unassigned 5", "Ann 1"])
        #expect(model.filterOptions(for: .parent).map { "\($0.title) \($0.count)" } == ["Issue epic 2"])
        #expect(model.filterOptions(for: .blocked).map { "\($0.title) \($0.count)" } == ["Blocked 1"])
        #expect(model.filterOptions(for: .updated).map(\.title) == ["24 hours", "7 days", "30 days", "90 days"])
    }

    @Test("clearing filters only clears the current view")
    func clearIsPerView() async {
        let model = await loadedModel()
        model.toggleFilterValue("1", in: .priority)
        model.source = .lifecycle(.inFlight)
        model.toggleFilterValue("ui", in: .labels)
        model.clearFilters()
        #expect(model.filter.rules.isEmpty)
        model.source = .lifecycle(.open)
        #expect(model.filter.rule(for: .priority) != nil)
    }

    @Test("groups have titles and follow the view's grouping and ordering")
    func groups() async {
        let model = await loadedModel()
        model.source = .lifecycle(.all)
        #expect(model.groups.map { "\($0.title) \($0.issues.count)" } == ["Open 2", "In Flight 2", "Closed 2"])
        #expect(model.groups[1].issues.map(\.id) == ["epic.2", "epic.1"])
        model.grouping = .none
        #expect(model.groups.count == 1)
        model.grouping = .priority
        #expect(model.groups.map(\.title) == ["P0", "P1", "P2"])
    }

    @Test("selection survives switching views")
    func selectionSurvives() async {
        let model = await loadedModel()
        model.selection = "todo"
        model.source = .lifecycle(.closed)
        #expect(model.selectedIssue?.id == "todo")
    }
}

@Suite("Display text")
struct DisplayTextTests {
    @Test("statuses, priorities, windows and fields read naturally")
    func text() {
        #expect(DisplayText.status("in_progress") == "In Progress")
        #expect(DisplayText.priority(0) == "P0")
        #expect(DisplayText.window(.month) == "30 days")
        #expect(DisplayText.scope(.inFlight) == "In Flight")
        #expect(DisplayText.category(.frozen) == "Deferred")
        #expect(DisplayText.field(.parent) == "Parent epic")
    }
}
