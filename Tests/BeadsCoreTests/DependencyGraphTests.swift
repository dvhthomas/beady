import BeadsCore
import Foundation
import Testing

@Suite("The dependency graph")
struct DependencyGraphTests {
    /// a → b → c (a has to finish first), a → d, and a separate pair x → y.
    /// "lonely" takes part in nothing and shouldn't appear.
    let snapshot = IssueSnapshot(issues: [
        makeIssue("a", title: "Tile cache"),
        makeIssue("b", title: "Download queue", blockedBy: ["a"]),
        makeIssue("c", title: "Background refresh", blockedBy: ["b"]),
        makeIssue("d", title: "Offline banner", blockedBy: ["a"]),
        makeIssue("x", title: "Ranking", status: "closed", closed: t0),
        makeIssue("y", title: "Typo tolerance", blockedBy: ["x"]),
        makeIssue("lonely", title: "Nothing to do with anything"),
    ])

    @Test("only beads that take part in a dependency are drawn")
    func nodes() {
        let graph = DependencyGraph(snapshot)
        #expect(Set(graph.nodes.map(\.id)) == ["a", "b", "c", "d", "x", "y"])
        #expect(graph.edges.count == 4)
    }

    @Test("finished beads can be left out, taking their edges with them")
    func hidingFinished() {
        let graph = DependencyGraph(snapshot, includeFinished: false)
        #expect(!graph.nodes.contains { $0.id == "x" })
        #expect(!graph.nodes.contains { $0.id == "y" }, "with its only edge gone, y has nothing to show")
        #expect(graph.edges.count == 3)
    }

    @Test("what can start now is on the left, and each bead sits one past its deepest blocker")
    func layers() {
        let graph = DependencyGraph(snapshot)
        #expect(graph.layer(of: "a") == 0)
        #expect(graph.layer(of: "b") == 1)
        #expect(graph.layer(of: "c") == 2)
        #expect(graph.layer(of: "d") == 1)
        #expect(graph.layer(of: "x") == 0)
        #expect(graph.layer(of: "y") == 1)
    }

    @Test("separate groups of work don't overlap")
    func components() {
        let graph = DependencyGraph(snapshot)
        #expect(graph.components.count == 2)
        let first = Set(graph.components[0])
        let second = Set(graph.components[1])
        #expect(first.isDisjoint(with: second))
        #expect(first.contains("a"), "the bigger group comes first")

        let positions = graph.layout()
        let rowsA = Set(graph.components[0].map { positions[$0]!.row })
        let rowsX = Set(graph.components[1].map { positions[$0]!.row })
        #expect(rowsA.isDisjoint(with: rowsX))
    }

    @Test("no two beads share a spot")
    func noOverlap() {
        let positions = DependencyGraph(snapshot).layout()
        let spots = positions.values.map { "\($0.column),\($0.row)" }
        #expect(Set(spots).count == spots.count)
    }

    @Test("upstream is everything that has to finish first; downstream everything waiting")
    func reach() {
        let graph = DependencyGraph(snapshot)
        #expect(graph.upstream(of: "c") == ["a", "b"])
        #expect(graph.directUpstream(of: "c") == ["b"])
        #expect(graph.downstream(of: "a") == ["b", "c", "d"])
        #expect(graph.upstream(of: "a").isEmpty)
    }

    @Test("a loop doesn't send any of this round forever")
    func cycles() {
        let looped = IssueSnapshot(issues: [
            makeIssue("p", blockedBy: ["q"]),
            makeIssue("q", blockedBy: ["p"]),
        ])
        let graph = DependencyGraph(looped)
        #expect(graph.upstream(of: "p") == ["q"])
        #expect(graph.downstream(of: "p") == ["q"])
        #expect(graph.layout().count == 2, "and still lays both out")
    }

    @Test("crossings are reduced where the order makes the difference")
    func ordering() {
        // Two blockers in one layer, each with its own dependent; a sensible order keeps the
        // lines parallel instead of crossing.
        let crossed = IssueSnapshot(issues: [
            makeIssue("b1"),
            makeIssue("a1"),
            makeIssue("a2", blockedBy: ["a1"]),
            makeIssue("b2", blockedBy: ["b1"]),
        ])
        let positions = DependencyGraph(crossed).layout()
        let upperFirst = positions["a1"]!.row < positions["b1"]!.row
        #expect((positions["a2"]!.row < positions["b2"]!.row) == upperFirst)
    }
}
