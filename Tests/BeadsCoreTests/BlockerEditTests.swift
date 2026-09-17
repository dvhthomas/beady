import BeadsCore
import Foundation
import Testing

@Suite("Changing what blocks a bead")
struct BlockerEditTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("a", title: "Tile cache"),
        makeIssue("b", title: "Download queue", blockedBy: ["a"]),
        makeIssue("c", title: "Stale tiles"),
        makeIssue("done", title: "Budget", status: "closed", closed: t0),
    ])

    @Test("adding and removing a blocker are their own changes")
    func shape() {
        #expect(IssueChange.setBlocker("b", blocker: "c", on: true).issueID == "b")
        #expect(IssueChange.setBlocker("b", blocker: "c", on: true).needsConfirmation, "the graph is worth confirming")
    }

    @Test("a bead can't block itself, or be blocked twice by the same bead")
    func refusals() {
        let itself = ChangeValidator.problems(for: .setBlocker("b", blocker: "b", on: true), in: snapshot)
        #expect(itself.map(\.code) == [.blockerIsSelf])

        let again = ChangeValidator.problems(for: .setBlocker("b", blocker: "a", on: true), in: snapshot)
        #expect(again.map(\.code) == [.noChange])

        let absent = ChangeValidator.problems(for: .setBlocker("b", blocker: "c", on: false), in: snapshot)
        #expect(absent.map(\.code) == [.noChange])

        let unknown = ChangeValidator.problems(for: .setBlocker("b", blocker: "ghost", on: true), in: snapshot)
        #expect(unknown.map(\.code) == [.unknownIssue])
    }

    @Test("a blocker that would close the loop is refused before bd is asked")
    func loops() {
        // a blocks b; making a wait on b would leave neither able to start.
        let loop = ChangeValidator.problems(for: .setBlocker("a", blocker: "b", on: true), in: snapshot)
        #expect(loop.map(\.code) == [.blockerLoops])
    }

    @Test("blocking on something already finished is allowed, but says so")
    func finished() {
        let problems = ChangeValidator.problems(for: .setBlocker("b", blocker: "done", on: true), in: snapshot)
        #expect(problems.map(\.code) == [.blockerIsDone])
        #expect(problems.allSatisfy { $0.severity == .warning })
    }

    @Test("the write is checked by reading the bead back")
    func verification() {
        var after = snapshot.issue("b")!
        after.dependencies = [
            Dependency(issueID: "b", dependsOnID: "a", kind: .blocks),
            Dependency(issueID: "b", dependsOnID: "c", kind: .blocks),
        ]
        #expect(ChangeGuard.mismatches(for: .setBlocker("b", blocker: "c", on: true), after: after).isEmpty)
        #expect(!ChangeGuard.mismatches(for: .setBlocker("b", blocker: "c", on: false), after: after).isEmpty)
    }
}
