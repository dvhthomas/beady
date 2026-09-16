import BeadsCore
import Foundation
import Testing

@Suite("IssueTree")
struct IssueTreeTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("epic", type: "epic"),
        makeIssue("epic.1", parent: "epic"),
        makeIssue("epic.2", parent: "epic"),
        makeIssue("epic.2.1", parent: "epic.2"),
        makeIssue("solo"),
    ])

    func shape(_ nodes: [IssueTreeNode]) -> String {
        nodes.map { node in
            let mark = node.isMatch ? "" : "~"
            let kids = node.children.isEmpty ? "" : "(\(shape(node.children)))"
            return "\(mark)\(node.id)\(kids)"
        }.joined(separator: " ")
    }

    @Test("builds the parent-child forest when everything matches")
    func fullForest() {
        let tree = IssueTree.build(matches: snapshot.issues, in: snapshot)
        #expect(shape(tree) == "epic(epic.1 epic.2(epic.2.1)) solo")
    }

    @Test("keeps unmatched ancestors as context so a match is never orphaned")
    func ancestorsAsContext() {
        let matches = [snapshot.issue("epic.2.1")!, snapshot.issue("solo")!]
        #expect(shape(IssueTree.build(matches: matches, in: snapshot)) == "~epic(~epic.2(epic.2.1)) solo")
    }

    @Test("sibling order follows the order of matches")
    func followsMatchOrder() {
        let matches = ["solo", "epic.2", "epic.1"].map { snapshot.issue(IssueID($0))! }
        #expect(shape(IssueTree.build(matches: matches, in: snapshot)) == "solo ~epic(epic.2 epic.1)")
    }

    @Test("parent cycles neither hang nor drop issues")
    func cycles() {
        let cyclic = IssueSnapshot(issues: [makeIssue("a", parent: "b"), makeIssue("b", parent: "a")])
        let tree = IssueTree.build(matches: cyclic.issues, in: cyclic)
        var seen: [IssueID] = []
        func walk(_ nodes: [IssueTreeNode]) { for n in nodes { seen.append(n.id); walk(n.children) } }
        walk(tree)
        #expect(Set(seen) == ["a", "b"])
        #expect(seen.count == 2)
    }
}

@Suite("IssueBoard")
struct IssueBoardTests {
    @Test("groups into lifecycle columns, hiding an empty frozen column")
    func columns() {
        let snapshot = IssueSnapshot(issues: [
            makeIssue("o"), makeIssue("w", status: "in_progress"), makeIssue("c", status: "closed", closed: t0),
        ])
        let columns = IssueBoard.columns(for: snapshot.issues, in: snapshot)
        #expect(columns.map(\.category) == [.active, .wip, .done])
        #expect(columns.map { $0.issues.map(\.id) } == [["o"], ["w"], ["c"]])
    }

    @Test("shows frozen when something is deferred")
    func frozenShown() {
        let snapshot = IssueSnapshot(issues: [makeIssue("f", status: "deferred")])
        let columns = IssueBoard.columns(for: snapshot.issues, in: snapshot)
        #expect(columns.map(\.category) == [.active, .wip, .frozen, .done])
    }
}
