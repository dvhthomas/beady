import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Views are remembered between launches")
struct ViewStatePersistenceTests {
    func makeModel(_ defaults: UserDefaults) async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("a", priority: 1, labels: ["offline"]),
            makeIssue("b", status: "in_progress", priority: 2),
        ])
        let model = WorkspaceModel(title: "demo", store: store, preferences: defaults, now: { t0 })
        await model.load()
        return model
    }

    func scratchDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "beady-tests-\(UUID().uuidString)")!
        return defaults
    }

    @Test("filters, layout, grouping and ordering come back per view")
    func roundTrip() async {
        let defaults = scratchDefaults()
        let model = await makeModel(defaults)
        model.viewID = .frontier
        model.toggleFilterValue("1", in: .priority)
        model.layout = .board
        model.grouping = .status
        model.ordering = .issueID
        model.searchText = "cache"
        model.viewID = .inFlight
        model.layout = .tree

        let reopened = await makeModel(defaults)
        reopened.viewID = .frontier
        #expect(reopened.filter.rule(for: .priority)?.values == ["1"])
        #expect(reopened.layout == .board)
        #expect(reopened.grouping == .status)
        #expect(reopened.ordering == .issueID)
        #expect(reopened.searchText == "cache", "a search is part of the view you left")
        reopened.viewID = .inFlight
        #expect(reopened.layout == .tree)
        #expect(reopened.filter == IssueView.builtIn(.inFlight)?.filter, "each view keeps its own")
    }

    @Test("a fresh workspace starts from the defaults, not from someone else's saved views")
    func emptyDefaults() async {
        let model = await makeModel(scratchDefaults())
        model.viewID = .inFlight
        #expect(model.grouping == .status, "In Flight groups by status out of the box")
        #expect(model.filter == IssueView.builtIn(.inFlight)?.filter)
    }

    @Test("a built-in's layout comes back after a relaunch, and it isn't a modification")
    func builtInPresentationSurvives() async {
        let defaults = scratchDefaults()
        let model = await makeModel(defaults)
        model.viewID = .frontier
        model.layout = .board
        model.grouping = .assignee
        let reopened = await makeModel(defaults)
        reopened.viewID = .frontier
        #expect(reopened.layout == .board)
        #expect(reopened.grouping == .assignee)
        #expect(!reopened.isModified)
    }

    @Test("a user view comes back with its filter, and an unsaved change comes back as modified")
    func userViewSurvives() async {
        let defaults = scratchDefaults()
        let model = await makeModel(defaults)
        model.toggleFilterValue("offline", in: .labels)
        let mine = model.saveAsNewView(name: "Offline")
        model.layout = .board

        let reopened = await makeModel(defaults)
        #expect(reopened.views.map(\.name).last == "Offline")
        reopened.viewID = mine.id
        #expect(reopened.view.filter.rule(for: .labels)?.values == ["offline"])
        #expect(reopened.layout == .board, "what was live comes back")
        #expect(reopened.isModified, "and is still unsaved")
        reopened.reset()
        #expect(reopened.layout == .list)
    }

    @Test("the old per-scope blob migrates: presentations land on the built-ins, rules become modified state, Open is offered as a user view")
    func migratesOldViewStates() async {
        let defaults = scratchDefaults()
        let old = """
        [
          {"source": {"lifecycle": {"_0": "all"}},
           "state": {"filter": {"rules": [], "searchText": ""}, "layout": "board", "grouping": "priority", "ordering": "issueID"}},
          {"source": {"lifecycle": {"_0": "inFlight"}},
           "state": {"filter": {"rules": [{"field": "labels", "op": "includesAll", "values": ["ui"]}], "searchText": ""},
                     "layout": "list", "grouping": "status", "ordering": "recentlyUpdated"}},
          {"source": {"lifecycle": {"_0": "open"}},
           "state": {"filter": {"rules": [{"field": "priority", "op": "isAnyOf", "values": ["1"]}], "searchText": "cache"},
                     "layout": "list", "grouping": "none", "ordering": "recentlyCreated"}},
          {"source": {"lifecycle": {"_0": "closed"}},
           "state": {"filter": {"rules": [], "searchText": ""}, "layout": "list", "grouping": "assignee", "ordering": "recentlyClosed"}},
          {"source": {"focused": {"_0": "epic"}},
           "state": {"filter": {"rules": [], "searchText": ""}, "layout": "tree", "grouping": "category", "ordering": "priority"}},
          {"source": {"label": {"_0": "starred"}},
           "state": {"filter": {"rules": [], "searchText": ""}, "layout": "board", "grouping": "category", "ordering": "priority"}}
        ]
        """
        defaults.set(Data(old.utf8), forKey: "viewStates")
        let model = await makeModel(defaults)

        // All → Everything, Closed → Landed, Starred → Starred: the remembered presentation lands.
        model.viewID = .everything
        #expect(model.layout == .board)
        #expect(model.grouping == .priority)
        #expect(model.ordering == .issueID)
        #expect(!model.isModified)
        model.viewID = .landed
        #expect(model.grouping == .assignee)
        model.viewID = .starred
        #expect(model.layout == .board)

        // In Flight carried a rule: it keeps its meaning and shows the rule as a modification.
        model.viewID = .inFlight
        #expect(model.filter.rule(for: .lifecycle) == IssueView.builtIn(.inFlight)?.filter.rule(for: .lifecycle))
        #expect(model.filter.rule(for: .labels)?.values == ["ui"])
        #expect(model.isModified)

        // Open has no built-in any more, so it is offered as a user view with everything it had.
        let open = try! #require(model.offeredViews.first)
        #expect(model.offeredViews.count == 1)
        #expect(open.name == "Open")
        #expect(!open.isBuiltIn)
        #expect(open.filter.rule(for: .lifecycle)?.values == [StatusCategory.active.rawValue])
        #expect(open.filter.rule(for: .priority)?.values == ["1"])
        #expect(open.filter.searchText == "cache")
        #expect(open.presentation.ordering == .recentlyCreated)
        #expect(!model.views.contains { $0.id == open.id }, "offered, not imposed")

        // The old blob is gone, and everything above survives another launch.
        #expect(defaults.data(forKey: "viewStates") == nil)
        let reopened = await makeModel(defaults)
        reopened.viewID = .everything
        #expect(reopened.layout == .board)
        #expect(reopened.offeredViews.map(\.name) == ["Open"])
        reopened.acceptOfferedView(open.id)
        #expect(reopened.offeredViews.isEmpty)
        #expect(reopened.views.last?.name == "Open")
        #expect(reopened.viewID == open.id)
        let again = await makeModel(defaults)
        #expect(again.views.last?.name == "Open")
        #expect(again.offeredViews.isEmpty)
    }

    @Test("an offered view can be declined, and stays declined")
    func decliningAnOffer() async {
        let defaults = scratchDefaults()
        let old = """
        [{"source": {"lifecycle": {"_0": "open"}},
          "state": {"filter": {"rules": [{"field": "priority", "op": "isAnyOf", "values": ["0"]}], "searchText": ""},
                    "layout": "list", "grouping": "none", "ordering": "priority"}}]
        """
        defaults.set(Data(old.utf8), forKey: "viewStates")
        let model = await makeModel(defaults)
        let open = try! #require(model.offeredViews.first)
        model.declineOfferedView(open.id)
        #expect(model.offeredViews.isEmpty)
        #expect((await makeModel(defaults)).offeredViews.isEmpty)
    }

    @Test("saved state that no longer makes sense is ignored rather than crashing")
    func corruptState() async {
        let defaults = scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: "viewStates")
        defaults.set(Data("not json".utf8), forKey: "views")
        defaults.set(Data("not json".utf8), forKey: "liveViews")
        let model = await makeModel(defaults)
        #expect(model.filter == IssueView.builtIn(.frontier)?.filter)
        model.layout = .board
        let reopened = await makeModel(defaults)
        #expect(reopened.layout == .board, "and it recovers by saving again")
    }
}
