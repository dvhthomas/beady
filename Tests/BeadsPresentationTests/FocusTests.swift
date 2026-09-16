import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Focus and progress, for any bead")
struct FocusTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("epic", title: "Print furniture", type: "epic"),
            makeIssue("epic.1", title: "Freeform positioning", parent: "epic"),
            makeIssue("epic.2", title: "Callout leader line", status: "closed", parent: "epic", closed: t0),
            // A plain task with children: focus and progress must work here too.
            makeIssue("task", title: "Tidy the renderer"),
            makeIssue("task.1", title: "Split the layout pass", parent: "task"),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return model
    }

    @Test("any bead can be focused, not just epics, and you can get back out")
    func focusAnyBead() async {
        let model = await makeModel()
        model.source = .lifecycle(.inFlight)
        model.focus(on: "task")
        #expect(model.source == .focused("task"))
        #expect(model.visibleIssues.map(\.id) == ["task.1"])
        model.unfocus()
        #expect(model.source == .lifecycle(.inFlight), "back to the view you came from")
    }

    @Test("the focused bead is named, so you can see where you are and leave")
    func breadcrumb() async {
        let model = await makeModel()
        #expect(model.focusedIssue == nil)
        model.focus(on: "epic")
        #expect(model.focusedIssue?.title == "Print furniture")
    }

    @Test("progress belongs to any bead with children")
    func progressColumn() async {
        let model = await makeModel()
        #expect(!ListColumn.progress.isVisibleByDefault, "opt in, like labels")
        #expect(model.progress(of: "epic") == Completion(closed: 1, total: 2))
        #expect(model.progress(of: "task") == Completion(closed: 0, total: 1))
        #expect(model.progress(of: "epic.1") == nil, "a leaf has no progress to show")
    }

    @Test("anything that already holds work can be a parent, not only epics")
    func parentChoices() async {
        let model = await makeModel()
        #expect(model.parentChoices(for: "task.1").map(\.id) == ["epic", "task"])
        #expect(model.parentChoices(for: "epic").map(\.id) == ["task"], "not itself, and not its own children")
    }

    @Test("grouping by parent puts the parent's progress in the header")
    func groupProgress() async {
        let model = await makeModel()
        model.source = .lifecycle(.all)
        model.grouping = .parent
        let group = try? #require(model.groups.first { $0.key == "epic" })
        #expect(group?.completion == Completion(closed: 1, total: 2))
        let ungrouped = model.groups.first { $0.key.isEmpty }
        #expect(ungrouped?.completion == nil, "\"No parent\" isn't a bead")
    }
}
