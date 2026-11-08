import BeadsCore
import Foundation
import Testing

@Suite("What has to finish before this can start")
struct UnblockTests {
    /// c is blocked by b, b by a; d blocks nothing and is already closed.
    let snapshot = IssueSnapshot(issues: [
        makeIssue("a", title: "Tile cache"),
        makeIssue("b", title: "Download queue", blockedBy: ["a"]),
        makeIssue("c", title: "Background refresh", blockedBy: ["b", "d"]),
        makeIssue("d", title: "Storage budget", status: "closed", closed: t0),
        makeIssue("free", title: "Nothing in the way"),
    ])

    @Test("the path is the unfinished work, in the order it can be done")
    func layers() {
        let path = UnblockPath.to("c", in: snapshot)
        #expect(path.layers.map { $0.map(\.id) } == [["a"], ["b"]], "a can start now; b waits for it")
        #expect(path.isBlocked)
        #expect(!path.layers.flatMap { $0 }.contains { $0.id == "d" }, "closed blockers are done, not work")
    }

    @Test("a bead nothing is holding up has no path")
    func notBlocked() {
        #expect(UnblockPath.to("free", in: snapshot).layers.isEmpty)
        #expect(!UnblockPath.to("free", in: snapshot).isBlocked)
        #expect(UnblockPath.to("a", in: snapshot).layers.isEmpty)
    }

    @Test("a diamond lands the shared blocker once, in the layer it can actually start")
    func diamond() {
        let diamond = IssueSnapshot(issues: [
            makeIssue("root"),
            makeIssue("left", blockedBy: ["root"]),
            makeIssue("right", blockedBy: ["root"]),
            makeIssue("goal", blockedBy: ["left", "right"]),
        ])
        let path = UnblockPath.to("goal", in: diamond)
        #expect(path.layers.map { $0.map(\.id) } == [["root"], ["left", "right"]])
        #expect(!path.hasCycle)
        #expect(path.work.map(\.id) == ["root", "left", "right"], "nearest first")
    }

    @Test("a blocker reached again by a longer route waits for that route, and appears once")
    func longerRoute() {
        // goal waits on a directly and through b: a must land in the farther layer.
        let graph = IssueSnapshot(issues: [
            makeIssue("a"),
            makeIssue("b", blockedBy: ["a"]),
            makeIssue("goal", blockedBy: ["a", "b"]),
        ])
        let path = UnblockPath.to("goal", in: graph)
        #expect(path.layers.map { $0.map(\.id) } == [["a"], ["b"]])
        #expect(!path.hasCycle)
    }

    @Test("a cycle among the blockers, not through the bead itself, is reported and terminates")
    func cycleBelowSubject() {
        let graph = IssueSnapshot(issues: [
            makeIssue("goal", blockedBy: ["p"]),
            makeIssue("p", blockedBy: ["q"]),
            makeIssue("q", blockedBy: ["p"]),
        ])
        let path = UnblockPath.to("goal", in: graph)
        #expect(path.hasCycle)
        #expect(Set(path.work.map(\.id)) == ["p", "q"], "each bead appears once")
    }

    @Test("a cycle is reported, not looped over")
    func cycles() {
        let looped = IssueSnapshot(issues: [
            makeIssue("x", blockedBy: ["y"]),
            makeIssue("y", blockedBy: ["x"]),
        ])
        let path = UnblockPath.to("x", in: looped)
        #expect(path.hasCycle)
        #expect(path.layers.flatMap { $0 }.count <= 2, "each bead appears once")
    }

    @Test("the neighbourhood is what to draw: blockers, dependents and children")
    func neighbourhood() {
        let graph = try! #require(IssueNeighbourhood.around("b", in: snapshot))
        #expect(graph.blockers.map(\.id) == ["a"])
        #expect(graph.dependents.map(\.id) == ["c"], "c waits on b")
        #expect(graph.subject.id == "b")
    }
}
