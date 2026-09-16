import BeadsCore
import Foundation
import Testing

@Suite("Scope")
struct ScopeTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("open-free"),
        makeIssue("open-blocked", blockedBy: ["wip"]),
        makeIssue("wip", status: "in_progress"),
        makeIssue("frozen", status: "deferred"),
        makeIssue("done", status: "closed", closed: t0),
    ])

    func ids(_ scope: Scope) -> Set<IssueID> {
        Set(snapshot.issues.filter { scope.includes($0, in: snapshot, now: t0) }.map(\.id))
    }

    @Test("each scope selects its slice of the lifecycle")
    func membership() {
        #expect(ids(.all).count == 5)
        #expect(ids(.open) == ["open-free", "open-blocked"])
        #expect(ids(.ready) == ["open-free"])
        #expect(ids(.inFlight) == ["wip"])
        #expect(ids(.blocked) == ["open-blocked"])
        #expect(ids(.deferred) == ["frozen"])
        #expect(ids(.closed) == ["done"])
    }

    @Test("ready leaves out open issues deferred into the future, as bd ready does")
    func readyRespectsDeferUntil() {
        let deferred = IssueSnapshot(issues: [
            makeIssue("later", deferUntil: t0 + days(1)),
            makeIssue("lapsed", deferUntil: t0 - days(1)),
        ])
        let ready = deferred.issues.filter { Scope.ready.includes($0, in: deferred, now: t0) }.map(\.id)
        #expect(ready == ["lapsed"])
        #expect(Scope.open.includes(deferred.issue("later")!, in: deferred, now: t0))
    }
}

@Suite("IssueSort")
struct IssueSortTests {
    let issues = [
        makeIssue("x", priority: 2, updated: t0 + hours(1)),
        makeIssue("y", priority: 1, updated: t0),
        makeIssue("z", priority: 2, updated: t0 + hours(2), closed: t0 + hours(3)),
        makeIssue("w", priority: 2, updated: t0 + hours(2), closed: t0 + hours(5)),
    ]

    @Test("priority first, then most recently updated, then id")
    func byPriority() {
        #expect(IssueSort.priority.sorted(issues).map(\.id) == ["y", "w", "z", "x"])
    }

    @Test("recently closed puts never-closed issues last")
    func byClosed() {
        #expect(IssueSort.recentlyClosed.sorted(issues).map(\.id) == ["w", "z", "x", "y"])
    }

    @Test("recently updated is newest first")
    func byUpdated() {
        #expect(IssueSort.recentlyUpdated.sorted(issues).map(\.id) == ["w", "z", "x", "y"])
    }
}
