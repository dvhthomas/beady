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

    @Test("any bead can be focused, not just epics: a parent chip on the view you're in")
    func focusAnyBead() async {
        let model = await makeModel()
        model.viewID = .everything
        model.focus(on: "task")
        #expect(model.viewID == .everything, "focus is a chip, not a view of its own")
        #expect(model.filter.rule(for: .parent) == FilterRule(field: .parent, op: .isAnyOf, values: ["task"]))
        #expect(model.visibleIssues.map(\.id) == ["task.1"])
        model.unfocus()
        #expect(model.filter.rule(for: .parent) == nil)
        #expect(model.visibleIssues.count == 5, "back to the whole view")
    }

    @Test("focusing adds a parent rule and leaves the rest of the view's filter intact; focusing again replaces it")
    func focusKeepsTheFilter() async {
        let model = await makeModel()
        model.viewID = .inFlight
        model.toggleFilterValue("1", in: .priority)
        model.focus(on: "task")
        #expect(model.filter.rule(for: .lifecycle) == IssueView.builtIn(.inFlight)?.filter.rule(for: .lifecycle))
        #expect(model.filter.rule(for: .priority)?.values == ["1"])
        #expect(model.filter.rule(for: .parent)?.values == ["task"])
        model.focus(on: "epic")
        #expect(model.filter.rule(for: .parent)?.values == ["epic"], "one focus at a time")
        #expect(model.filter.rules.count == 3)
        model.unfocus()
        #expect(model.filter.rules.map(\.field) == [.lifecycle, .priority])
    }

    @Test("the focused bead is named, so you can see where you are and leave")
    func breadcrumb() async {
        let model = await makeModel()
        #expect(model.focusedIssue == nil)
        model.focus(on: "epic")
        #expect(model.focusedIssue?.title == "Print furniture")
        // The breadcrumb is the chip, so the chip row doesn't show the parent rule a second time.
        #expect(!model.filterChips.contains { $0.field == .parent })
        // A parent rule that isn't a focus — several parents, or "not under" — is an ordinary chip.
        model.setFilterOperator(.isNoneOf, for: .parent)
        #expect(model.focusedIssue == nil)
        #expect(model.filterChips.contains { $0.field == .parent })
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
        model.viewID = .everything
        model.grouping = .parent
        let group = try? #require(model.groups.first { $0.key == "epic" })
        #expect(group?.completion == Completion(closed: 1, total: 2))
        let ungrouped = model.groups.first { $0.key.isEmpty }
        #expect(ungrouped?.completion == nil, "\"No parent\" isn't a bead")
    }
}
