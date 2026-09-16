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
        model.source = .lifecycle(.open)
        model.toggleFilterValue("1", in: .priority)
        model.layout = .board
        model.grouping = .status
        model.ordering = .issueID
        model.searchText = "cache"
        model.source = .lifecycle(.inFlight)
        model.layout = .tree

        let reopened = await makeModel(defaults)
        reopened.source = .lifecycle(.open)
        #expect(reopened.filter.rules.first?.values == ["1"])
        #expect(reopened.layout == .board)
        #expect(reopened.grouping == .status)
        #expect(reopened.ordering == .issueID)
        #expect(reopened.searchText == "cache", "a search is part of the view you left")
        reopened.source = .lifecycle(.inFlight)
        #expect(reopened.layout == .tree)
        #expect(reopened.filter.isEmpty, "each view keeps its own")
    }

    @Test("a fresh workspace starts from the defaults, not from someone else's saved views")
    func emptyDefaults() async {
        let model = await makeModel(scratchDefaults())
        model.source = .lifecycle(.inFlight)
        #expect(model.grouping == .status, "In Flight groups by status out of the box")
        #expect(model.filter.isEmpty)
    }

    @Test("saved state that no longer makes sense is ignored rather than crashing")
    func corruptState() async {
        let defaults = scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: "viewStates")
        let model = await makeModel(defaults)
        #expect(model.filter.isEmpty)
        model.layout = .board
        let reopened = await makeModel(defaults)
        #expect(reopened.layout == .board, "and it recovers by saving again")
    }
}
