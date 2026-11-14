import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Re-reading the Library folder while the window is open")
struct ReloadViewsTests {
    func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("beady-reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func makeView(_ name: String, id: String) -> IssueView {
        IssueView(
            id: IssueView.ID(id), name: name, symbol: "bookmark",
            filter: ViewFilter(rules: [FilterRule(field: .labels, op: .includesAny, values: [name.lowercased()])]),
            presentation: ViewPresentation(layout: .board, grouping: .status, ordering: .priority)
        )
    }

    func makeModel(viewsDirectory: URL?) async -> WorkspaceModel {
        let model = WorkspaceModel(
            title: "demo", store: StubStore([makeIssue("a")]), viewsDirectory: viewsDirectory, now: { t0 }
        )
        await model.load()
        return model
    }

    @Test("a view file dropped into the folder appears after reloadViews, and what's live survives")
    func fileAdded() async throws {
        let directory = try scratchDirectory()
        let model = await makeModel(viewsDirectory: directory)
        model.searchText = "live typing"

        try makeView("Tiles", id: "tiles").documentData()
            .write(to: directory.appendingPathComponent("tiles.beadyview"))
        #expect(!model.views.contains { $0.id == IssueView.ID("tiles") }, "the folder only speaks when asked")

        model.reloadViews()
        #expect(model.views.first { $0.id == IssueView.ID("tiles") }?.name == "Tiles")
        #expect(model.searchText == "live typing", "the unsaved filter state stayed")
    }

    @Test("a view file changed on disk — a sync, a hand edit — is picked up too")
    func fileChanged() async throws {
        let directory = try scratchDirectory()
        try makeView("Tiles", id: "tiles").documentData()
            .write(to: directory.appendingPathComponent("tiles.beadyview"))
        let model = await makeModel(viewsDirectory: directory)
        #expect(model.views.first { $0.id == IssueView.ID("tiles") }?.name == "Tiles")
        model.searchText = "still here"

        var renamed = makeView("Agent tiles", id: "tiles")
        renamed.filter = ViewFilter(rules: [FilterRule(field: .priority, op: .isAnyOf, values: ["0"])])
        try renamed.documentData().write(to: directory.appendingPathComponent("tiles.beadyview"))
        model.reloadViews()

        let reloaded = model.views.first { $0.id == IssueView.ID("tiles") }
        #expect(reloaded?.name == "Agent tiles")
        #expect(reloaded?.filter == renamed.filter)
        #expect(model.searchText == "still here")
    }

    @Test("without a Library folder, reloadViews leaves everything alone")
    func noDirectory() async {
        let model = await makeModel(viewsDirectory: nil)
        let mine = model.saveAsNewView(name: "Mine")
        model.searchText = "typed"

        model.reloadViews()
        #expect(model.views.contains { $0.id == mine.id }, "the in-memory view wasn't thrown away")
        #expect(model.viewID == mine.id)
        #expect(model.searchText == "typed")
    }
}

@MainActor
@Suite("Arrows on a board whose sub-tasks are folded into their parent's card")
struct BoardCollapsedChildNavigationTests {
    /// Active column: the card `p` (holding the folded child `p.1`) then `z`;
    /// In Flight column: `c` then `d`.
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("p", priority: 0),
            makeIssue("p.1", priority: 1, parent: "p"),
            makeIssue("z", priority: 2),
            makeIssue("c", status: "in_progress", priority: 0),
            makeIssue("d", status: "in_progress", priority: 1),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        model.viewID = .everything
        model.layout = .board
        model.grouping = .category
        model.ordering = .priority
        model.nestsSubtasks = true
        return model
    }

    @Test("the fixture folds as described: p holds p.1, and cards start collapsed")
    func arrangement() async {
        let model = await makeModel()
        let active = model.boardColumns.first { $0.key == StatusCategory.active.rawValue }
        #expect(active?.cards.map(\.id) == ["p", "z"])
        #expect(active?.cards.first?.children.map(\.id) == ["p.1"])
        #expect(model.boardExpanded.isEmpty)
    }

    @Test("a selected child inside a collapsed card stands where its card does: down lands on the next card")
    func downFromHiddenChild() async {
        let model = await makeModel()
        model.selection = "p.1"
        model.moveSelection(.down)
        #expect(model.selection == "z", "from p's row, not from nowhere")
    }

    @Test("crossing columns from a hidden child keeps the card's row")
    func acrossFromHiddenChild() async {
        let model = await makeModel()
        model.selection = "p.1"
        model.moveSelection(.right)
        #expect(model.selection == "c", "row 0, where the card p stands")
    }

    @Test("once the card is expanded, the child is a row of its own and the arrows start there")
    func expandedChildIsItsOwnRow() async {
        let model = await makeModel()
        model.toggleBoardCard("p")
        model.selection = "p.1"
        model.moveSelection(.right)
        #expect(model.selection == "d", "row 1 now, so the next column's row 1")

        model.selection = "p.1"
        model.moveSelection(.up)
        #expect(model.selection == "p")
    }
}
