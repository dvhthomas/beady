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
        model.source = .lifecycle(.all)
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

    @Test("the sidebar is lifecycle views only; beads are reached from the main panel")
    func sidebarIsNavigationOnly() async {
        let model = await loadedModel()
        #expect(model.sidebarViews.allSatisfy { if case .lifecycle = $0.source { true } else { false } })
        // What the epics section used to provide, available for any bead that holds work:
        #expect(model.progress(of: "epic") == Completion(closed: 0, total: 2))
    }

    @Test("showing a subtree opens that issue's view as a tree")
    func focusOnSubtree() async {
        let model = await loadedModel()
        model.focus(on: "epic.1")
        #expect(model.source == .focused("epic.1"))
        #expect(model.layout == .tree)
        #expect(model.visibleIssues.map(\.id) == ["epic.1.1"])
    }
}
