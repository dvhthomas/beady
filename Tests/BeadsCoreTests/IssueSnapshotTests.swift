import BeadsCore
import Foundation
import Testing

@Suite("IssueID")
struct IssueIDTests {
    @Test("sorts naturally so .2 comes before .10")
    func naturalOrder() {
        let ids: [IssueID] = ["bd-a.10", "bd-a.2", "bd-a", "bd-a.1"]
        #expect(ids.sorted() == ["bd-a", "bd-a.1", "bd-a.2", "bd-a.10"])
    }
}

@Suite("StatusCatalog")
struct StatusCatalogTests {
    @Test("built-in statuses map to bd's categories")
    func builtIn() {
        let catalog = StatusCatalog.builtIn
        #expect(catalog.category(of: "open") == .active)
        #expect(catalog.category(of: "in_progress") == .wip)
        #expect(catalog.category(of: "blocked") == .wip)
        #expect(catalog.category(of: "hooked") == .wip)
        #expect(catalog.category(of: "deferred") == .frozen)
        #expect(catalog.category(of: "pinned") == .frozen)
        #expect(catalog.category(of: "closed") == .done)
    }

    @Test("custom categories override built-ins; unknown statuses count as active")
    func customAndUnknown() {
        let catalog = StatusCatalog(["review": .wip, "open": .frozen])
        #expect(catalog.category(of: "review") == .wip)
        #expect(catalog.category(of: "open") == .frozen)
        #expect(catalog.category(of: "closed") == .done)
        #expect(catalog.category(of: "mystery") == .active)
    }
}

@Suite("IssueSnapshot")
struct IssueSnapshotTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("epic", type: "epic", labels: ["plan", "lane"]),
        makeIssue("epic.1", status: "closed", assignee: "Ann", parent: "epic", closed: t0),
        makeIssue("epic.2", status: "in_progress", assignee: "Bo", labels: ["lane"], parent: "epic"),
        makeIssue("epic.2.1", parent: "epic.2", blockedBy: ["epic.1", "epic.2", "gone"]),
        makeIssue("loose", status: "open", blockedBy: ["epic.2"]),
        makeIssue("stuck", status: "blocked"),
        makeIssue("done-but-linked", status: "closed", blockedBy: ["epic.2"], closed: t0),
    ])

    @Test("looks up issues and children in natural id order")
    func lookup() {
        #expect(snapshot.issue("epic.2")?.assignee == "Bo")
        #expect(snapshot.issue("nope") == nil)
        #expect(snapshot.children(of: "epic").map(\.id) == ["epic.1", "epic.2"])
    }

    @Test("ancestors are nearest first")
    func ancestors() {
        let leaf = snapshot.issue("epic.2.1")!
        #expect(snapshot.ancestors(of: leaf).map(\.id) == ["epic.2", "epic"])
        #expect(snapshot.isDescendant(leaf, of: "epic"))
        #expect(!snapshot.isDescendant(leaf, of: "loose"))
    }

    @Test("ancestors survive a parent cycle")
    func ancestorCycle() {
        let cyclic = IssueSnapshot(issues: [makeIssue("a", parent: "b"), makeIssue("b", parent: "a")])
        #expect(cyclic.ancestors(of: cyclic.issue("a")!).map(\.id) == ["b"])
    }

    @Test("only unfinished, existing blockers count")
    func openBlockers() {
        let leaf = snapshot.issue("epic.2.1")!
        #expect(snapshot.openBlockers(of: leaf).map(\.id) == ["epic.2"])
        #expect(snapshot.isBlocked(leaf))
        #expect(snapshot.dependents(of: "epic.2").map(\.id) == ["done-but-linked", "epic.2.1", "loose"])
    }

    @Test("blocked status blocks; closed issues are never blocked")
    func blockedStatus() {
        #expect(snapshot.isBlocked(snapshot.issue("stuck")!))
        #expect(!snapshot.isBlocked(snapshot.issue("done-but-linked")!))
        #expect(!snapshot.isBlocked(snapshot.issue("epic")!))
    }

    @Test("progress counts closed descendants, not just direct children")
    func progress() {
        #expect(snapshot.progress(of: "epic") == Completion(closed: 1, total: 3))
        #expect(snapshot.progress(of: "epic.2") == Completion(closed: 0, total: 1))
        #expect(snapshot.progress(of: "loose") == nil)
    }

    @Test("facets are unique and sorted")
    func facets() {
        #expect(snapshot.labels == ["lane", "plan"])
        #expect(snapshot.assignees == ["Ann", "Bo"])
        #expect(snapshot.types == ["epic", "task"])
        #expect(snapshot.statuses == ["blocked", "closed", "in_progress", "open"])
        #expect(snapshot.priorities == [2])
    }

    @Test("external dependencies count as open blockers, as bd treats them until shipped")
    func externalBlockers() {
        let external = IssueSnapshot(issues: [
            makeIssue("a", blockedBy: ["external:other-project:capability"]),
            makeIssue("b", status: "closed", blockedBy: ["external:other-project:capability"], closed: t0),
        ])
        let a = external.issue("a")!
        #expect(external.externalBlockers(of: a) == ["external:other-project:capability"])
        #expect(external.isBlocked(a))
        #expect(!external.isBlocked(external.issue("b")!))
    }
}
