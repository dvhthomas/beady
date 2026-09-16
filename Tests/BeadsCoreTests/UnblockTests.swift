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
