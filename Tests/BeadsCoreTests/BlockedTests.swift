import BeadsCore
import Foundation
import Testing

@Suite("Why a bead is waiting")
struct BlockedTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("upstream", title: "Tile cache", status: "in_progress", assignee: "Ada"),
        makeIssue("waiting", title: "Download queue", blockedBy: ["upstream"]),
        makeIssue("declared", title: "Stale tiles", status: "blocked"),
        makeIssue("both", title: "Refresh", status: "blocked", blockedBy: ["upstream"]),
        makeIssue("done-blocker", title: "Budget", status: "closed", closed: t0),
        makeIssue("settled", title: "Nothing in the way", blockedBy: ["done-blocker"]),
        makeIssue("elsewhere", title: "Refunds", blockedBy: ["external:payments:refunds"]),
    ])

    @Test("waiting on an unfinished bead names it")
    func waitingOnBead() {
        let reason = try! #require(BlockedReason.of("waiting", in: snapshot))
        #expect(reason.blockers.map(\.id) == ["upstream"])
        #expect(reason.kind == .waitingOnBeads)
        #expect(!reason.isDeclaredOnly)
    }

    @Test("a bead whose blockers are all finished isn't waiting for anything")
    func settled() {
        #expect(BlockedReason.of("settled", in: snapshot) == nil)
        #expect(BlockedReason.of("upstream", in: snapshot) == nil)
    }

    @Test("status set to blocked with nothing upstream is its own case, and says so")
    func declaredOnly() {
        let reason = try! #require(BlockedReason.of("declared", in: snapshot))
        #expect(reason.kind == .declared)
        #expect(reason.blockers.isEmpty)
        #expect(reason.isDeclaredOnly, "bd records no reason for this, so the app shouldn't pretend to know one")
    }

    @Test("both at once reports the beads, since those are the actionable part")
    func both() {
        let reason = try! #require(BlockedReason.of("both", in: snapshot))
        #expect(reason.kind == .waitingOnBeads)
        #expect(reason.blockers.map(\.id) == ["upstream"])
        #expect(reason.isDeclared, "and still notes that someone marked it blocked")
    }

    @Test("a dependency on another project is named as such")
    func external() {
        let reason = try! #require(BlockedReason.of("elsewhere", in: snapshot))
        #expect(reason.kind == .waitingOnAnotherProject)
        #expect(reason.externalCapabilities == ["payments:refunds"])
    }

    @Test("the summary is the fastest answer: who is holding it up")
    func summary() {
        #expect(BlockedReason.of("waiting", in: snapshot)?.summary == "Waiting on upstream")
        #expect(BlockedReason.of("declared", in: snapshot)?.summary == "Marked blocked")
        #expect(BlockedReason.of("elsewhere", in: snapshot)?.summary == "Waiting on payments:refunds")
    }
}
