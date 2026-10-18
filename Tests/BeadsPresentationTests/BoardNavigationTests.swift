import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Moving around the board with the keyboard")
struct BoardNavigationTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("a", priority: 0),
            makeIssue("b", priority: 1),
            makeIssue("c", status: "in_progress"),
            makeIssue("d", status: "closed", closed: t0),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        model.viewID = .everything
        model.layout = .board
        model.grouping = .category
        model.ordering = .priority
        return model
    }

    @Test("with nothing selected, the first card takes the highlight")
    func firstCard() async {
        let model = await makeModel()
        model.moveSelection(.down)
        #expect(model.selection == "a")
    }

    @Test("up and down move within a column and stop at its ends")
    func withinColumn() async {
        let model = await makeModel()
        model.selection = "a"
        model.moveSelection(.down)
        #expect(model.selection == "b")
        model.moveSelection(.down)
        #expect(model.selection == "b", "the bottom of the column is the bottom")
        model.moveSelection(.up)
        #expect(model.selection == "a")
        model.moveSelection(.up)
        #expect(model.selection == "a")
    }

    @Test("left and right cross columns, keeping your place down the column")
    func acrossColumns() async {
        let model = await makeModel()
        model.selection = "a"
        model.moveSelection(.right)
        #expect(model.selection == "c", "same row in the next column")
        model.moveSelection(.left)
        #expect(model.selection == "a")
        model.moveSelection(.left)
        #expect(model.selection == "a", "the first column is the first column")

        model.selection = "b"
        model.moveSelection(.right)
        #expect(model.selection == "c", "a shorter column lands you on its last card")
    }

    @Test("moving only applies to the board; the list and tree have their own")
    func boardOnly() async {
        let model = await makeModel()
        model.layout = .list
        model.selection = "a"
        model.moveSelection(.right)
        #expect(model.selection == "a")
    }
}

@MainActor
@Suite("A board that is one column says so")
struct BoardSplittingTests {
    /// Every active bead is "open" or a custom active status, so lifecycle columns collapse to one.
    func makeModel() async -> WorkspaceModel {
        let snapshot = IssueSnapshot(issues: [
            makeIssue("a", priority: 0, assignee: "Ann", parent: "epic"),
            makeIssue("b", status: "triage", priority: 1),
            makeIssue("epic", type: "epic"),
            makeIssue("done", status: "closed", closed: t0),
        ], catalog: StatusCatalog(["triage": .active]))
        let model = WorkspaceModel(title: "demo", store: StubStore([.success(snapshot)]), now: { t0 })
        await model.load()
        model.viewID = .everything
        model.toggleFilterValue(StatusCategory.active.rawValue, in: .lifecycle)
        model.layout = .board
        model.grouping = .none
        return model
    }

    @Test("a board on 'lifecycle is active' with no grouping needs splitting, and says which groupings would")
    func oneColumn() async {
        let model = await makeModel()
        #expect(model.boardGroups.filter { !$0.issues.isEmpty }.count == 1)
        #expect(model.boardNeedsSplitting?.groupings == [.status, .priority, .assignee, .parent])
    }

    @Test("a grouping that spreads the cards out is enough")
    func split() async {
        let model = await makeModel()
        model.grouping = .priority
        #expect(model.boardNeedsSplitting == nil)
    }

    @Test("only groupings that would actually split the board are offered")
    func onlyUsefulGroupings() async {
        let model = await makeModel()
        model.toggleFilterValue(FilterRule.unassigned, in: .assignee)
        // b and the epic are left: both unassigned, neither under a parent, so those two can't help.
        #expect(model.boardNeedsSplitting?.groupings == [.status, .priority])
        model.toggleFilterValue("Ann", in: .assignee)
        model.toggleFilterValue(FilterRule.unassigned, in: .assignee)
        // One card: nothing splits one card, so there is nothing to say.
        #expect(model.visibleIssues.count == 1)
        #expect(model.boardNeedsSplitting == nil)
    }

    @Test("a list doesn't care")
    func listsDontCare() async {
        let model = await makeModel()
        model.layout = .list
        #expect(model.boardNeedsSplitting == nil)
    }
}
