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

    @Test("limited to a set of beads, only edges with both ends inside survive")
    func limited() {
        let graph = DependencyGraph(snapshot, limitedTo: ["a", "b", "c"])
        #expect(Set(graph.nodes.map(\.id)) == ["a", "b", "c"])
        #expect(graph.edges.count == 2)
        #expect(!graph.nodes.contains { $0.id == "d" }, "a → d has one end outside, so d is gone entirely")
        #expect(!graph.nodes.contains { $0.id == "x" })
    }

    @Test("limited to nothing in particular, the graph is the whole database")
    func unlimited() {
        let scoped = DependencyGraph(snapshot, limitedTo: nil)
        let whole = DependencyGraph(snapshot)
        #expect(scoped.edges == whole.edges)
        #expect(scoped.nodes.map(\.id) == whole.nodes.map(\.id))
    }

    @Test("the limit composes with leaving finished work out")
    func limitedWithoutFinished() {
        let graph = DependencyGraph(snapshot, limitedTo: ["a", "b", "x", "y"], includeFinished: false)
        #expect(Set(graph.nodes.map(\.id)) == ["a", "b"], "x is done, so x → y goes too")
    }

    @Test("direct downstream mirrors direct upstream")
    func directDownstream() {
        let graph = DependencyGraph(snapshot)
        #expect(graph.directDownstream(of: "a") == ["b", "d"])
        #expect(graph.directDownstream(of: "c").isEmpty)
        #expect(graph.directUpstream(of: "b") == ["a"])
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

@Suite("Walking the graph with the arrows")
struct GraphNeighbourTests {
    /// A diamond: a → b → d and a → c → d.
    let diamond = IssueSnapshot(issues: [
        makeIssue("a"),
        makeIssue("b", blockedBy: ["a"]),
        makeIssue("c", blockedBy: ["a"]),
        makeIssue("d", blockedBy: ["b", "c"]),
    ])

    @Test("left and right walk direct blockers and dependents, and stop at the ends")
    func leftRight() {
        let graph = DependencyGraph(diamond)
        let left = graph.neighbour(of: "d", direction: .left)
        #expect(left.map { graph.directUpstream(of: "d").contains($0) } == true)
        let right = graph.neighbour(of: "a", direction: .right)
        #expect(right.map { graph.directDownstream(of: "a").contains($0) } == true)
        #expect(graph.neighbour(of: "a", direction: .left) == nil, "nothing blocks a")
        #expect(graph.neighbour(of: "d", direction: .right) == nil, "nothing waits on d")
    }

    @Test("the nearest row wins a sideways step")
    func nearestRow() {
        let graph = DependencyGraph(diamond)
        let positions = graph.layout()
        let left = graph.neighbour(of: "d", direction: .left)!
        let other: IssueID = left == "b" ? "c" : "b"
        let dRow = positions["d"]!.row
        #expect(abs(positions[left]!.row - dRow) <= abs(positions[other]!.row - dRow))
    }

    @Test("up and down step through a column")
    func upDown() {
        let graph = DependencyGraph(diamond)
        let positions = graph.layout()
        let upper: IssueID = positions["b"]!.row < positions["c"]!.row ? "b" : "c"
        let lower: IssueID = upper == "b" ? "c" : "b"
        #expect(graph.neighbour(of: upper, direction: .down) == lower)
        #expect(graph.neighbour(of: lower, direction: .up) == upper)
        #expect(graph.neighbour(of: upper, direction: .up) == nil, "the top of the column is the top")
    }

    @Test("with nothing focused, an arrow enters at the top left")
    func entry() {
        let graph = DependencyGraph(diamond)
        #expect(graph.neighbour(of: nil, direction: .down) == "a")
        #expect(graph.neighbour(of: "unknown", direction: .up) == "a")
    }

    @Test("down steps across into the next group of work")
    func acrossComponents() {
        let two = IssueSnapshot(issues: [
            makeIssue("a"), makeIssue("b", blockedBy: ["a"]),
            makeIssue("x"), makeIssue("y", blockedBy: ["x"]),
        ])
        let graph = DependencyGraph(two)
        let positions = graph.layout()
        let upper: IssueID = positions["a"]!.row < positions["x"]!.row ? "a" : "x"
        let lower: IssueID = upper == "a" ? "x" : "a"
        #expect(graph.neighbour(of: upper, direction: .down) == lower)
    }
}
