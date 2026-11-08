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

    @Test("a status picked in Ready doesn't leak into In Flight, and is still there back in Ready")
    func filtersArePerView() async {
        let model = await loadedModel()
        #expect(model.viewID == .frontier)
        #expect(model.filter == IssueView.builtIn(.frontier)?.filter, "a built-in starts from its own filter")
        model.toggleFilterValue("open", in: .status)
        #expect(model.visibleIssues.map(\.id) == ["todo", "epic"])

        model.viewID = .inFlight
        #expect(model.filter == IssueView.builtIn(.inFlight)?.filter)
        #expect(Set(model.visibleIssues.map(\.id)) == ["epic.1", "epic.2"])

        model.viewID = .frontier
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

        model.viewID = .inFlight
        #expect(model.layout == .list)
        #expect(model.grouping == .status)
        #expect(model.ordering == .recentlyUpdated)
        #expect(model.searchText == "")

        model.viewID = .frontier
        #expect(model.layout == .board)
        #expect(model.grouping == .priority)
        #expect(model.ordering == .issueID)
        #expect(model.searchText == "todo")
    }

    @Test("each built-in view starts with its own display")
    func defaults() async {
        let model = await loadedModel()
        #expect(model.grouping == .none)
        #expect(model.ordering == .priority)
        model.viewID = .landed
        #expect(model.ordering == .recentlyClosed)
        model.viewID = .everything
        #expect(model.grouping == .category)
        #expect(model.ordering == .recentlyUpdated)
        model.viewID = .pipeline
        #expect(model.layout == .board)
    }

    @Test("the status filter only offers statuses the view's Lifecycle rule allows")
    func statusOptionsFollowView() async {
        let model = await loadedModel()
        model.viewID = .inFlight
        #expect(model.filterOptions(for: .status).map { "\($0.title) \($0.count)" } == ["Blocked 1", "In Progress 1"])
        model.viewID = .landed
        #expect(model.filterOptions(for: .status).map(\.title) == ["Closed"])
    }

    @Test("sidebar counts are each built-in's own total, whatever you've added to it")
    func sidebarCounts() async {
        let model = await loadedModel()
        // Pipeline keeps everything live plus a week of done; Recent is a day of updates; nothing is starred.
        let expected = ["Pipeline 6", "Ready 2", "In Flight 2", "Stuck 1", "Recent 6", "Landed 2", "Deferred 0", "Everything 6"]
        #expect(model.sidebarViews.map { "\($0.title) \($0.count)" } == expected)
        model.toggleFilterValue("ui", in: .labels)
        #expect(model.sidebarViews.map { "\($0.title) \($0.count)" } == expected)
        #expect(model.sidebarViews.map(\.id) == IssueView.builtIns.map(\.id).filter { $0 != .starred })
    }

    @Test("focusing on a bead is a parent chip on the view you're in, so its filters still apply")
    func focusChip() async {
        let model = await loadedModel()
        model.viewID = .everything
        model.toggleFilterValue("ui", in: .labels)
        model.focus(on: "epic")
        #expect(model.filter.rule(for: .labels)?.values == ["ui"])
        #expect(Set(model.visibleIssues.map(\.id)) == ["epic.1", "epic.2"])
        #expect(model.viewTitle == "Everything", "the view keeps its name; the breadcrumb names the bead")
        #expect(model.focusedIssue?.title == "Issue epic")
        model.viewID = .inFlight
        #expect(model.viewTitle == "In Flight")
        #expect(model.focusedIssue == nil, "focus belongs to the view it was pushed onto")
    }

    @Test("chips read like Linear's: field, operator, values")
    func chips() async {
        let model = await loadedModel()
        model.viewID = .everything
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

    @Test("lifecycle chips name bd's categories; ready reads 'is yes'")
    func lifecycleAndReadyChips() async {
        let model = await loadedModel()
        model.viewID = .everything
        model.toggleFilterValue("wip", in: .lifecycle)
        model.toggleFilterValue("active", in: .lifecycle)
        #expect(chipText(model) == ["Lifecycle | is any of | Active, In Flight"])
        model.toggleFilterValue(FilterRule.readyValue, in: .ready)
        #expect(chipText(model).last == "Ready | is | yes")
        #expect(model.filterOptions(for: .lifecycle).map(\.title) == ["Active", "In Flight", "Frozen", "Done"])
        #expect(model.filterOptions(for: .ready).map(\.title) == ["yes"])
    }

    @Test("filter menu options have readable titles and counts")
    func optionTitles() async {
        let model = await loadedModel()
        model.viewID = .everything
        #expect(model.filterOptions(for: .assignee).map { "\($0.title) \($0.count)" } == ["Unassigned 5", "Ann 1"])
        #expect(model.filterOptions(for: .parent).map { "\($0.title) \($0.count)" } == ["Issue epic 2"])
        #expect(model.filterOptions(for: .blocked).map { "\($0.title) \($0.count)" } == ["Blocked 1"])
        #expect(model.filterOptions(for: .updated).map(\.title) == ["24 hours", "7 days", "30 days", "90 days"])
    }

    @Test("clearing filters only clears the current view")
    func clearIsPerView() async {
        let model = await loadedModel()
        model.toggleFilterValue("1", in: .priority)
        model.viewID = .inFlight
        model.toggleFilterValue("ui", in: .labels)
        model.clearFilters()
        // Clear removes what was added; a built-in's own rule is locked (bdv-jlx.12).
        #expect(model.filter == IssueView.builtIn(.inFlight)?.filter)
        model.viewID = .frontier
        #expect(model.filter.rule(for: .priority) != nil)
    }

    @Test("groups have titles and follow the view's grouping and ordering")
    func groups() async {
        let model = await loadedModel()
        model.viewID = .everything
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
        model.viewID = .landed
        #expect(model.selectedIssue?.id == "todo")
    }
}

@MainActor
@Suite("Built-in views keep a fixed filter; user views remember everything")
struct ViewSavingTests {
    func loadedModel() async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore([
            makeIssue("a", priority: 1),
            makeIssue("b", priority: 2, assignee: "Ann"),
            makeIssue("c", status: "in_progress"),
        ]), now: { t0 })
        await model.load()
        return model
    }

    @Test("adding a rule to Ready marks it modified; save is refused, Save as new view keeps the filter")
    func builtInFilterIsFixed() async {
        let model = await loadedModel()
        #expect(model.viewID == .frontier)
        #expect(!model.isModified)
        model.toggleFilterValue("1", in: .priority)
        #expect(model.isModified)
        #expect(!model.save(), "a built-in's filter is its definition")
        #expect(model.isModified)
        #expect(IssueView.builtIn(.frontier)?.filter.rule(for: .priority) == nil)

        let urgent = model.saveAsNewView(name: "Urgent")
        #expect(model.viewID == urgent.id)
        #expect(model.view.name == "Urgent")
        #expect(!model.view.isBuiltIn)
        #expect(model.view.filter.rule(for: .priority)?.values == ["1"])
        #expect(model.view.filter.rule(for: .ready) != nil, "it starts from everything Ready meant")
        #expect(!model.isModified)
        #expect(model.views.map(\.id).last == urgent.id)
        #expect(model.visibleIssues.map(\.id) == ["a"])

        model.viewID = .frontier
        #expect(!model.isModified, "Ready is back to what it means")
        #expect(model.filter == IssueView.builtIn(.frontier)?.filter)
    }

    @Test("changing a built-in's layout is remembered, not a modification")
    func builtInPresentationIsRemembered() async {
        let model = await loadedModel()
        model.layout = .board
        model.grouping = .status
        #expect(!model.isModified)
        #expect(model.view.presentation.layout == .board)
        model.viewID = .everything
        model.viewID = .frontier
        #expect(model.layout == .board)
        #expect(model.grouping == .status)
    }

    @Test("a user view's layout change marks it modified, and save clears that")
    func userViewRemembersEverything() async {
        let model = await loadedModel()
        let mine = model.saveAsNewView(name: "Mine")
        #expect(!model.isModified)
        model.layout = .board
        #expect(model.isModified)
        #expect(model.save())
        #expect(!model.isModified)
        #expect(model.views.first { $0.id == mine.id }?.presentation.layout == .board)
        model.toggleFilterValue("Ann", in: .assignee)
        #expect(model.isModified)
        model.save()
        #expect(model.views.first { $0.id == mine.id }?.filter.rule(for: .assignee)?.values == ["Ann"])
    }

    @Test("reset puts the saved view back, filter and presentation alike")
    func reset() async {
        let model = await loadedModel()
        model.saveAsNewView(name: "Mine")
        model.toggleFilterValue("Ann", in: .assignee)
        model.layout = .tree
        model.ordering = .issueID
        model.searchText = "x"
        #expect(model.isModified)
        model.reset()
        #expect(!model.isModified)
        #expect(model.filter.rule(for: .assignee) == nil)
        #expect(model.layout == .list)
        #expect(model.ordering == .priority)
        #expect(model.searchText == "")

        model.viewID = .frontier
        model.toggleFilterValue("1", in: .priority)
        model.reset()
        #expect(model.filter == IssueView.builtIn(.frontier)?.filter)
    }

    @Test("a user view can be removed; a built-in can't")
    func removing() async {
        let model = await loadedModel()
        let mine = model.saveAsNewView(name: "Mine")
        #expect(model.removeView(mine.id))
        #expect(!model.views.contains { $0.id == mine.id })
        #expect(model.viewID == .pipeline, "back to the first built-in")
        #expect(!model.removeView(.frontier))
        #expect(model.views.count == IssueView.builtIns.count)
    }

    @Test("a user view can be renamed; blank names and built-ins are refused")
    func renaming() async {
        let model = await loadedModel()
        let mine = model.saveAsNewView(name: "Mine")
        #expect(model.renameView(mine.id, to: "  Ours  "))
        #expect(model.view.name == "Ours", "trimmed")
        #expect(!model.renameView(mine.id, to: "   "))
        #expect(model.view.name == "Ours")
        #expect(!model.renameView(.frontier, to: "Front"))
        #expect(IssueView.builtIn(.frontier)?.name == "Ready")
    }

    @Test("duplicating copies the saved view as a user view named after it, right after the original")
    func duplicating() async {
        let model = await loadedModel()
        let mine = model.saveAsNewView(name: "Mine")
        model.layout = .board
        let copy = try! #require(model.duplicateView(mine.id))
        #expect(copy.name == "Mine copy")
        #expect(!copy.isBuiltIn)
        #expect(copy.presentation.layout == .list, "the saved view is copied, not what's live")
        #expect(copy.filter == mine.filter)
        #expect(model.views.map(\.id).suffix(2) == [mine.id, copy.id])
        #expect(model.viewID == mine.id, "duplicating doesn't move you")

        // A built-in can be duplicated too: that's how you get a variation without modifying it.
        let frontier = try! #require(model.duplicateView(.frontier))
        #expect(frontier.name == "Ready copy")
        #expect(!frontier.isBuiltIn)
        #expect(frontier.filter == IssueView.builtIn(.frontier)?.filter)
        #expect(model.views.filter { !$0.isBuiltIn }.map(\.name) == ["Mine", "Mine copy", "Ready copy"], "user views sit after the built-ins, in name order")
        #expect(model.duplicateView(IssueView.ID("nope")) == nil)
    }

    @Test("importing a document adds the views under My Views and shows the last one; export writes the saved view")
    func importAndExport() async throws {
        let model = await loadedModel()
        let mine = model.saveAsNewView(name: "Mine")
        model.layout = .board
        let data = try #require(try model.exportDocument(for: mine.id))
        let exported = try #require(try ViewLibrary.views(fromDocument: data).first)
        #expect(exported.presentation.layout == .list, "what's saved, not what's live")

        let imported = try model.importViews(fromDocument: data)
        #expect(imported.map(\.name) == ["Mine (imported)"])
        #expect(model.viewID == imported[0].id)
        #expect(model.sidebarSections[1].entries.map(\.title) == ["Mine", "Mine (imported)"])
        #expect(try model.exportDocument(for: IssueView.ID("nope")) == nil)
    }

    @Test("the current view carries its live filter and presentation")
    func liveView() async {
        let model = await loadedModel()
        model.toggleFilterValue("1", in: .priority)
        model.layout = .board
        #expect(model.view.id == .frontier)
        #expect(model.view.filter.rule(for: .priority)?.values == ["1"])
        #expect(model.view.presentation.layout == .board)
        #expect(model.view.isBuiltIn)
    }
}

@MainActor
@Suite("Built-in views are locked: you duplicate them, you don't edit them")
struct LockedBuiltInTests {
    func loadedModel() async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore([
            makeIssue("a", priority: 1),
            makeIssue("b", priority: 2, assignee: "Ann"),
            makeIssue("c", status: "in_progress"),
        ]), now: { t0 })
        await model.load()
        return model
    }

    @Test("a built-in's defining chip is locked: remove, operator and toggle leave the filter unchanged")
    func lockedChip() async {
        let model = await loadedModel()
        #expect(model.viewID == .frontier)
        #expect(model.filterChips.map { "\($0.field) \($0.isLocked)" } == ["ready true"])
        #expect(model.isLocked(.ready))
        #expect(!model.isLocked(.priority))
        let frontier = model.filter
        model.removeFilter(.ready)
        #expect(model.filter == frontier)
        model.toggleFilterValue(FilterRule.readyValue, in: .ready)
        #expect(model.filter == frontier, "unticking the locked value is refused too")

        model.viewID = .inFlight
        let inFlight = model.filter
        model.setFilterOperator(.isNoneOf, for: .lifecycle)
        #expect(model.filter == inFlight)
        model.toggleFilterValue(StatusCategory.active.rawValue, in: .lifecycle)
        #expect(model.filter == inFlight)
        #expect(!model.isModified)
    }

    @Test("Clear removes only what was added on top of a built-in")
    func clearKeepsTheDefinition() async {
        let model = await loadedModel()
        #expect(!model.hasClearableFilters, "the defining rule alone is nothing to clear")
        model.toggleFilterValue("1", in: .priority)
        #expect(model.hasClearableFilters)
        #expect(model.filterChips.map { "\($0.field) \($0.isLocked)" } == ["ready true", "priority false"])
        model.clearFilters()
        #expect(model.filter == IssueView.builtIn(.frontier)?.filter)
        #expect(!model.isModified)
        #expect(!model.hasClearableFilters)
    }

    @Test("a user view has no locked chips, even one saved from a built-in")
    func userViewsAreUnlocked() async {
        let model = await loadedModel()
        model.toggleFilterValue("1", in: .priority)
        model.saveAsNewView(name: "Urgent")
        #expect(model.filterChips.allSatisfy { !$0.isLocked })
        #expect(!model.isLocked(.ready))
        model.removeFilter(.ready)
        #expect(model.filter.rule(for: .ready) == nil)
        #expect(model.hasClearableFilters)
    }

    @Test("duplicating a built-in gives an unlocked user view with the same filter, presentation and symbol")
    func duplicateBuiltIn() async {
        let model = await loadedModel()
        let frontier = IssueView.builtIn(.frontier)!
        let copy = try! #require(model.duplicateView(.frontier))
        #expect(!copy.isBuiltIn)
        #expect(copy.filter == frontier.filter)
        #expect(copy.presentation == frontier.presentation)
        #expect(copy.symbol == frontier.symbol)
        model.viewID = copy.id
        #expect(model.filterChips.allSatisfy { !$0.isLocked })
        #expect(model.sidebarSections[1].entries.map(\.title) == ["Ready copy"])
    }

    @Test("a modified built-in offers Save as new view and Reset, never Save; a built-in's name can't change")
    func saveControl() async {
        let model = await loadedModel()
        model.toggleFilterValue("1", in: .priority)
        #expect(model.isModified)
        #expect(!model.canSave)
        let commands = CommandCatalog.results(for: "", model: model)
        #expect(commands.contains(.saveViewAs) && commands.contains(.resetView) && !commands.contains(.saveView))
        #expect(!model.renameView(.frontier, to: "Mine"))
        model.saveAsNewView(name: "Urgent")
        model.layout = .board
        #expect(model.canSave)
    }
}

@Suite("Display text")
struct DisplayTextTests {
    @Test("the empty details pane says what the arrows do, only when they do something")
    func noSelection() {
        let plain = DisplayText.noSelection(canGoBack: false, canGoForward: false)
        #expect(plain == "Select a bead to see its details.")
        let back = DisplayText.noSelection(canGoBack: true, canGoForward: false)
        #expect(back.contains("go back") && back.contains("⌘[") && !back.contains("⌘]"))
        let forward = DisplayText.noSelection(canGoBack: false, canGoForward: true)
        #expect(forward.contains("forward") && forward.contains("⌘]") && !forward.contains("⌘["))
        let both = DisplayText.noSelection(canGoBack: true, canGoForward: true)
        #expect(both.contains("⌘[") && both.contains("⌘]"))
        for text in [plain, back, forward, both] {
            #expect(text.hasPrefix("Select a bead") && text.hasSuffix("."), Comment(rawValue: text))
        }
    }

    @Test("statuses, priorities, windows and fields read naturally")
    func text() {
        #expect(DisplayText.status("in_progress") == "In Progress")
        #expect(DisplayText.priority(0) == "P0")
        #expect(DisplayText.window(.month) == "30 days")
        #expect(DisplayText.category(.frozen) == "Deferred")
        #expect(DisplayText.field(.parent) == "Parent epic")
        #expect(DisplayText.field(.lifecycle) == "Lifecycle")
        #expect(DisplayText.field(.ready) == "Ready")
        #expect(DisplayText.lifecycle(.active) == "Active")
        #expect(DisplayText.lifecycle(.wip) == "In Flight")
    }
}
