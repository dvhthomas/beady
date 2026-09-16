import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Pinning and starring through the model")
struct ModelMarkTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        let store = MemoryStore([
            makeIssue("a", title: "Tile cache", priority: 2),
            makeIssue("b", title: "Download queue", priority: 1, labels: ["pinned"]),
            makeIssue("c", title: "Stale tiles", priority: 3, labels: ["starred"]),
            makeIssue("d", title: "Crash on cancel", status: "in_progress", priority: 0),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return (model, store)
    }

    @Test("pinned beads lead every view, whatever the ordering")
    func pinnedLead() async {
        let (model, _) = await makeModel()
        model.source = .lifecycle(.all)
        model.ordering = .priority
        #expect(model.visibleIssues.map(\.id) == ["b", "d", "a", "c"], "b is pinned; the rest by priority")
        model.ordering = .issueID
        #expect(model.visibleIssues.first?.id == "b")
    }

    @Test("Starred is a view of the label, listed in the sidebar with its count")
    func starredView() async {
        let (model, _) = await makeModel()
        let starred = model.sidebarViews.first { $0.source == .label(IssueMark.starred.label) }
        let entry = try! #require(starred)
        #expect(entry.title == "Starred")
        #expect(entry.count == 1)
        model.source = .label(IssueMark.starred.label)
        #expect(model.visibleIssues.map(\.id) == ["c"])
        #expect(model.viewTitle == "Starred")
    }

    @Test("the Starred view disappears when nothing is starred, rather than sitting there empty")
    func starredHidesWhenEmpty() async {
        let store = MemoryStore([makeIssue("a")])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        #expect(!model.sidebarViews.contains { $0.source == .label(IssueMark.starred.label) })
    }

    @Test("toggling a mark writes the label through the store and needs no confirmation")
    func toggling() async {
        let (model, store) = await makeModel()
        await model.toggleMark(.starred, on: "a")
        #expect(store.applied == [.setMark("a", .starred, on: true)])
        #expect(model.pendingChange == nil, "a label is reversible metadata, not a content edit")

        await model.toggleMark(.pinned, on: "b")
        #expect(store.applied.last == .setMark("b", .pinned, on: false), "already pinned, so this unpins")
    }

    @Test("a read-only workspace can't pin or star")
    func readOnly() async {
        let model = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a")]), allowsWriting: false, now: { t0 })
        await model.load()
        await model.toggleMark(.pinned, on: "a")
        #expect(model.activity.isEmpty)
    }

    @Test("the starred filter is an ordinary label rule, so it reads as a normal chip")
    func starredFilter() async {
        let (model, _) = await makeModel()
        model.source = .lifecycle(.all)
        model.toggleMarkFilter(.starred)
        #expect(model.filter.rules.first?.field == .labels)
        #expect(model.visibleIssues.map(\.id) == ["c"])
        #expect(model.filterChips.first?.valuesTitle == "starred")
        model.toggleMarkFilter(.starred)
        #expect(model.filter.isEmpty)
    }
}
