import BeadsCore
import Foundation
import Testing

@Suite("Activity log: what other sessions have been doing")
struct ActivityLogTests {
    let log = ActivityLog(entries: [
        ActivityEntry(issueID: "a", actor: "Dylan Thomas", date: t0 + 100, field: "status"),
        ActivityEntry(issueID: "b", actor: "Dylan Thomas", date: t0 + 90, field: "title"),
        ActivityEntry(issueID: "a", actor: "Dylan Thomas", date: t0 + 50, field: "notes"),
        ActivityEntry(issueID: "c", actor: "agent-7", date: t0 - 600, field: "status"),
    ])

    @Test("the newest change to a bead inside the window wins")
    func latest() {
        #expect(log.latestChange(to: "a", since: t0)?.date == t0 + 100)
        #expect(log.latestChange(to: "b", since: t0)?.field == "title")
        #expect(log.latestChange(to: "c", since: t0) == nil, "older than the window")
        #expect(log.latestChange(to: "ghost", since: t0) == nil)
    }

    @Test("our own writes don't count as another session, matched by when we wrote")
    func excludesOurOwnWrites() {
        #expect(log.latestChange(to: "a", since: t0, excluding: [t0 + 100]) == nil)
        #expect(log.latestChange(to: "a", since: t0, excluding: [t0 + 100, t0 + 50])?.date == nil)
        #expect(log.latestChange(to: "a", since: t0, excluding: [t0 + 99.5])?.date == nil, "within the tolerance")
        #expect(log.latestChange(to: "a", since: t0, excluding: [t0 + 80])?.date == t0 + 100)
    }

    @Test("everything touched since a moment, for deciding what to reload")
    func changedSince() {
        #expect(log.issuesChanged(since: t0) == ["a", "b"])
        #expect(log.issuesChanged(since: t0 + 95) == ["a"])
        #expect(ActivityLog.empty.issuesChanged(since: t0).isEmpty)
    }
}
