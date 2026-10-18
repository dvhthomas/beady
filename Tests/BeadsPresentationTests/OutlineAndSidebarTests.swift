import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@Suite("Outline rows")
struct OutlineRowTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("epic", type: "epic"),
        makeIssue("epic.1", parent: "epic"),
        makeIssue("epic.1.1", parent: "epic.1"),
        makeIssue("epic.2", parent: "epic"),
        makeIssue("solo"),
    ])

    func describe(_ rows: [OutlineRow]) -> [String] {
        rows.map { row in
            let marker = row.hasChildren ? (row.isExpanded ? "v " : "> ") : "  "
            return String(repeating: ".", count: row.depth) + marker + row.id.rawValue
        }
    }

    @Test("flattens depth first, fully expanded by default")
    func expanded() {
        let tree = IssueTree.build(matches: snapshot.issues, in: snapshot)
        #expect(describe(OutlineRow.flatten(tree, collapsed: [])) == [
            "v epic", ".v epic.1", "..  epic.1.1", ".  epic.2", "  solo",
        ])
    }

    @Test("a collapsed branch keeps its row and hides its descendants")
    func collapsed() {
        let tree = IssueTree.build(matches: snapshot.issues, in: snapshot)
        #expect(describe(OutlineRow.flatten(tree, collapsed: ["epic.1"])) == [
            "v epic", ".> epic.1", ".  epic.2", "  solo",
        ])
        #expect(describe(OutlineRow.flatten(tree, collapsed: ["epic"])) == ["> epic", "  solo"])
    }
}

@MainActor
@Suite("WorkspaceModel outline and epics")
struct WorkspaceModelOutlineTests {
    func loadedModel() async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore([
            makeIssue("epic", type: "epic"),
            makeIssue("epic.1", parent: "epic"),
            makeIssue("epic.1.1", parent: "epic.1"),
            makeIssue("done-epic", status: "closed", type: "epic", closed: t0),
            makeIssue("done-epic.1", status: "closed", parent: "done-epic", closed: t0),
        ]), now: { t0 })
        await model.load()
        model.viewID = .everything
        return model
    }

    @Test("toggling expansion collapses and re-expands one branch")
    func toggleExpansion() async {
        let model = await loadedModel()
        #expect(model.outlineRows.map(\.id) == ["done-epic", "done-epic.1", "epic", "epic.1", "epic.1.1"])
        model.toggleExpansion(of: "epic.1")
        #expect(model.outlineRows.map(\.id) == ["done-epic", "done-epic.1", "epic", "epic.1"])
        model.toggleExpansion(of: "epic.1")
        #expect(model.outlineRows.count == 5)
    }

    @Test("collapse all leaves only roots; expand all restores everything")
    func collapseAndExpandAll() async {
        let model = await loadedModel()
        model.collapseAll()
        #expect(model.outlineRows.map(\.id) == ["done-epic", "epic"])
        model.expandAll()
        #expect(model.outlineRows.count == 5)
    }

    @Test("the sidebar is built-in views only; beads are reached from the main panel")
    func sidebarIsNavigationOnly() async {
        let model = await loadedModel()
        #expect(model.sidebarViews.allSatisfy { IssueView.builtIn($0.id)?.isBuiltIn == true })
        // What the epics section used to provide, available for any bead that holds work:
        #expect(model.progress(of: "epic") == Completion(closed: 0, total: 2))
    }

    @Test("user views follow the built-ins in the sidebar, with their own counts")
    func userViewsInSidebar() async {
        let model = await loadedModel()
        model.toggleFilterValue("epic", in: .type)
        let epics = model.saveAsNewView(name: "Epics")
        let entry = try! #require(model.sidebarViews.last)
        #expect(entry.id == epics.id)
        #expect(entry.title == "Epics")
        #expect(entry.symbol == epics.symbol)
        #expect(entry.count == 2)
        #expect(model.sidebarViews.dropLast().allSatisfy { IssueView.builtIn($0.id) != nil })
    }

    @Test("the sidebar is Views, then My Views with its +, then Starred only once something is starred")
    func sections() async {
        let model = await loadedModel()
        #expect(model.sidebarSections.map(\.kind) == [.views, .mine])
        #expect(model.sidebarSections.map(\.title) == ["Views", "My Views"])
        #expect(model.sidebarSections.map(\.canAdd) == [false, true])
        #expect(model.sidebarSections[0].entries.map(\.id) == IssueView.builtIns.map(\.id).filter { $0 != .starred })
        #expect(model.sidebarSections[1].entries.isEmpty, "the section is there for its +")

        model.saveAsNewView(name: "Mine")
        #expect(model.sidebarSections[1].entries.map(\.title) == ["Mine"])

        let starred = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a", labels: [IssueMark.starred.label])]), now: { t0 })
        await starred.load()
        #expect(starred.sidebarSections.map(\.kind) == [.views, .mine, .starred])
        #expect(starred.sidebarSections.last?.entries.map(\.id) == [.starred])
        #expect(starred.sidebarSections.last?.title == "")
        #expect(starred.sidebarViews.map(\.id) == starred.sidebarSections.flatMap { $0.entries.map(\.id) })
    }

    @Test("each row knows its layout and whether it has unsaved changes")
    func rowGlyphs() async {
        let model = await loadedModel()
        func entry(_ id: IssueView.ID) -> SidebarEntry? { model.sidebarViews.first { $0.id == id } }
        #expect(entry(.pipeline)?.layout == .board)
        #expect(entry(.frontier)?.layout == .list)
        #expect(entry(.frontier)?.isBuiltIn == true)
        #expect(entry(.everything)?.isModified == false)
        model.toggleFilterValue("epic", in: .type)
        #expect(entry(.everything)?.isModified == true)
        #expect(entry(.frontier)?.isModified == false, "only the view that changed")
        model.viewID = .frontier
        model.layout = .board
        #expect(entry(.frontier)?.layout == .board, "the glyph follows the remembered layout")
        #expect(entry(.frontier)?.isModified == false, "a built-in's layout is never a modification")
        let mine = model.saveAsNewView(name: "Mine")
        model.layout = .tree
        #expect(entry(mine.id)?.isBuiltIn == false)
        #expect(entry(mine.id)?.layout == .tree, "a user view's glyph shows what's live")
        #expect(entry(mine.id)?.isModified == true)
    }

    @Test("showing a subtree narrows the current view to what's under the bead")
    func focusOnSubtree() async {
        let model = await loadedModel()
        model.layout = .tree
        model.focus(on: "epic.1")
        #expect(model.focusedIssue?.id == "epic.1")
        // Focus is a chip on the view (bdv-jlx.2), so the layout is the view's own, not forced to a tree.
        #expect(model.layout == .tree)
        #expect(model.visibleIssues.map(\.id) == ["epic.1.1"])
    }
}
