import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@Suite("Folding sub-tasks into their parents' board cards")
struct BoardNestingTests {
    /// An epic with two tasks in different columns, a grandchild under one of them, and a bead
    /// of its own.
    let issues = [
        makeIssue("epic", priority: 0, type: "epic"),
        makeIssue("task1", priority: 1, parent: "epic"),
        makeIssue("task2", status: "in_progress", priority: 1, parent: "epic"),
        makeIssue("grand", priority: 2, parent: "task2"),
        makeIssue("solo", priority: 3),
    ]
    var snapshot: IssueSnapshot { IssueSnapshot(issues: issues) }

    /// Category columns built by hand, so each test says exactly what the board starts from.
    /// (`BeadsCore.Issue`: Swift Testing has an `Issue` of its own.)
    func columns(nesting: Bool, showing visible: [BeadsCore.Issue]? = nil) -> [BoardColumnModel] {
        let shown = visible ?? issues
        return BoardNesting.columns(from: [
            IssueGroupModel(key: "active", title: "Open", issues: shown.filter { $0.status == "open" }),
            IssueGroupModel(key: "wip", title: "In Flight", issues: shown.filter { $0.status == "in_progress" }),
        ], in: snapshot, nesting: nesting)
    }

    func cards(_ columns: [BoardColumnModel], _ key: String) -> [IssueID] {
        columns.first { $0.key == key }!.cards.map(\.id)
    }

    @Test("off, every bead is its own card, exactly as grouped")
    func passThrough() {
        let board = columns(nesting: false)
        #expect(cards(board, "active") == ["epic", "task1", "grand", "solo"])
        #expect(cards(board, "wip") == ["task2"])
        #expect(board.flatMap(\.cards).allSatisfy { $0.children.isEmpty })
    }

    @Test("on, a sub-task folds into its parent's card — from another column too")
    func folds() {
        let board = columns(nesting: true)
        #expect(cards(board, "active") == ["epic", "grand", "solo"])
        #expect(cards(board, "wip").isEmpty, "task2 folded into the epic's card across columns")
        let epic = board[0].cards.first { $0.id == "epic" }!
        #expect(epic.children.map(\.id) == ["task1", "task2"])
    }

    @Test("one level only: the child of a folded bead keeps its own card")
    func oneLevel() {
        let board = columns(nesting: true)
        #expect(cards(board, "active").contains("grand"), "task2 folded, so grand has no card to fold into")
        let everyBead = board.flatMap { $0.cards.flatMap { [$0.id] + $0.children.map(\.id) } }
        #expect(everyBead.sorted() == ["epic", "grand", "solo", "task1", "task2"], "nothing disappears, nothing doubles")
    }

    @Test("a bead whose parent the filter left out keeps its card")
    func filteredParent() {
        let board = columns(nesting: true, showing: issues.filter { $0.id != "epic" })
        #expect(cards(board, "active") == ["task1", "solo"])
        #expect(cards(board, "wip") == ["task2"], "and with its parent carded again, grand folds into task2")
        #expect(board[1].cards[0].children.map(\.id) == ["grand"])
    }

    @Test("a child row carries its own subtree progress; a leaf carries none")
    func childCompletion() {
        let epic = columns(nesting: true)[0].cards.first { $0.id == "epic" }!
        let task1 = epic.children.first { $0.id == "task1" }!
        let task2 = epic.children.first { $0.id == "task2" }!
        #expect(task1.completion == nil)
        #expect(task2.completion == snapshot.progress(of: "task2"))
        #expect(task2.completion != nil)
    }

    @Test("a parent loop doesn't hang, and every bead still appears exactly once")
    func cycle() {
        let looped = IssueSnapshot(issues: [
            makeIssue("p", parent: "q"),
            makeIssue("q", parent: "p"),
        ])
        let board = BoardNesting.columns(
            from: [IssueGroupModel(key: "active", title: "Open", issues: looped.issues)],
            in: looped, nesting: true
        )
        let everyBead = board.flatMap { $0.cards.flatMap { [$0.id] + $0.children.map(\.id) } }
        #expect(everyBead.sorted() == ["p", "q"])
    }

    @Test("what can be landed on: cards, and the children of expanded cards only")
    func selectable() {
        let board = columns(nesting: true)
        #expect(BoardNesting.selectableIDs(in: board[0], expanded: []) == ["epic", "grand", "solo"])
        #expect(BoardNesting.selectableIDs(in: board[0], expanded: ["epic"]) == ["epic", "task1", "task2", "grand", "solo"])
    }
}

@MainActor
@Suite("The board nesting option on the model")
struct BoardNestingModelTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("epic", priority: 0, type: "epic"),
            makeIssue("task1", priority: 1, parent: "epic"),
            makeIssue("task2", status: "in_progress", priority: 1, parent: "epic"),
            makeIssue("solo", priority: 3),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        model.viewID = .everything
        model.layout = .board
        model.grouping = .category
        model.ordering = .priority
        return model
    }

    @Test("the option folds the board, and parent grouping turns it off")
    func optionAndParentGrouping() async {
        let model = await makeModel()
        #expect(!model.nestsSubtasks, "off is the default")
        model.nestsSubtasks = true
        #expect(model.nestsSubtasks)
        let active = model.boardColumns.first { $0.key == StatusCategory.active.rawValue }!
        #expect(active.cards.first { $0.id == "epic" }!.children.map(\.id) == ["task1", "task2"])

        model.grouping = .parent
        #expect(!model.nestsSubtasks, "the columns are the parents already")
        model.grouping = .category
        #expect(model.nestsSubtasks, "the stored choice waits out the detour")
    }

    @Test("the arrows walk into an expanded card's children and skip a collapsed one")
    func arrows() async {
        let model = await makeModel()
        model.nestsSubtasks = true
        model.selection = "epic"
        model.moveSelection(.down)
        #expect(model.selection == "solo", "collapsed children are skipped")

        model.toggleBoardCard("epic")
        model.selection = "epic"
        model.moveSelection(.down)
        #expect(model.selection == "task1")
        model.moveSelection(.down)
        #expect(model.selection == "task2", "the cross-column child is in this card's run")
        model.moveSelection(.down)
        #expect(model.selection == "solo")
        model.moveSelection(.up)
        #expect(model.selection == "task2")
    }

    @Test("a selected child inside a card that collapses still anchors the arrows")
    func collapseUnderSelection() async {
        let model = await makeModel()
        model.nestsSubtasks = true
        model.toggleBoardCard("epic")
        model.selection = "task1"
        model.toggleBoardCard("epic")
        model.moveSelection(.down)
        #expect(model.selection == "solo", "the hidden child stands where its card does")
    }

    @Test("on a user view the option waits for Save, like the rest of the presentation")
    func savedWithTheView() async {
        let model = await makeModel()
        let mine = model.saveAsNewView(name: "Mine")
        model.viewID = mine.id
        #expect(!model.isModified)
        model.nestsSubtasks = true
        #expect(model.isModified, "changed but not saved")
        #expect(model.save())
        #expect(!model.isModified)
        #expect(model.views.first { $0.id == mine.id }?.presentation.nestsSubtasks == true)

        model.nestsSubtasks = false
        #expect(model.isModified)
        model.reset()
        #expect(model.nestsSubtasks, "reset goes back to the view as saved")
    }
}
