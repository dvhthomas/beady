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

/// A view never opens on a board that can't split: Board stays the preference, the list is what
/// you see until the data spreads out or you ask for the board anyway.
@MainActor
@Suite("A board that can't split opens as a list")
struct BoardFallbackTests {
    /// Every live bead is open, so lifecycle columns collapse to one.
    static let oneColumn = [
        makeIssue("a", priority: 0, assignee: "Ann", parent: "epic"),
        makeIssue("b", priority: 1),
        makeIssue("epic", type: "epic"),
    ]
    /// Open, in progress and freshly done: three lifecycle columns.
    static let spread = [
        makeIssue("a", priority: 0),
        makeIssue("b", status: "in_progress", priority: 1),
        makeIssue("c", status: "closed", closed: t0),
    ]

    func makeModel(_ issues: [BeadsCore.Issue], preferences: UserDefaults? = nil) async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore(issues), preferences: preferences, now: { t0 })
        await model.load()
        return model
    }

    @Test("Pipeline over one-column fixtures presents as a list with its grouping intact; over spread fixtures as the board")
    func pipelineFallsBack() async {
        let model = await makeModel(Self.oneColumn)
        model.viewID = .pipeline
        #expect(model.layout == .board, "Board is still the preference")
        #expect(model.presentedLayout == .list)
        #expect(model.isBoardShownAsList)
        #expect(model.grouping == .category)
        #expect(model.ordering == .priority)
        #expect(model.view.presentation.layout == .board, "the remembered presentation is untouched")
        #expect(!model.isModified)

        let spread = await makeModel(Self.spread)
        spread.viewID = .pipeline
        #expect(spread.presentedLayout == .board)
        #expect(!spread.isBoardShownAsList)
    }

    @Test("an explicit Board choice shows the split state, and is forgotten on view change and relaunch")
    func explicitBoard() async {
        let defaults = UserDefaults(suiteName: "beady-tests-\(UUID().uuidString)")!
        let model = await makeModel(Self.oneColumn, preferences: defaults)
        model.viewID = .pipeline
        model.chooseLayout(.board)
        #expect(model.presentedLayout == .board)
        #expect(model.boardNeedsSplitting?.groupings == [.priority, .assignee, .parent])
        #expect(!model.isBoardShownAsList)

        model.showBoardAsList()
        #expect(model.presentedLayout == .list)
        #expect(model.layout == .board, "showing the list doesn't give up the preference")

        model.chooseLayout(.board)
        model.viewID = .everything
        model.viewID = .pipeline
        #expect(model.presentedLayout == .list, "forgotten on view change")

        model.chooseLayout(.board)
        let relaunched = await makeModel(Self.oneColumn, preferences: defaults)
        relaunched.viewID = .pipeline
        #expect(relaunched.layout == .board, "the remembered presentation came back")
        #expect(relaunched.presentedLayout == .list, "the explicit choice did not")
    }

    @Test("the fallback never applies to a list or a tree, and the setter counts as an explicit choice")
    func onlyBoards() async {
        let model = await makeModel(Self.oneColumn)
        #expect(model.viewID == .frontier)
        #expect(model.presentedLayout == .list)
        model.layout = .tree
        #expect(model.presentedLayout == .tree)
        model.layout = .board
        #expect(model.presentedLayout == .board, "asking for the board gets the board, split state and all")
        #expect(model.boardNeedsSplitting != nil)
    }

    @Test("the board comes back by itself once the data spreads out")
    func boardReturns() async {
        let store = StubStore([.success(IssueSnapshot(issues: Self.oneColumn)), .success(IssueSnapshot(issues: Self.spread))])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        model.viewID = .pipeline
        #expect(model.presentedLayout == .list)
        await model.load()
        #expect(model.presentedLayout == .board)
    }
}

