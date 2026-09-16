import BeadsCore
import Foundation
import Testing

@Suite("Issue history")
struct HistoryTests {
    func version(_ offset: TimeInterval, _ apply: (inout BeadsCore.Issue) -> Void) -> IssueVersion {
        var issue = Issue(
            id: "a", title: "Tile cache", status: "open", priority: 2, type: "task",
            createdAt: t0, updatedAt: t0 + offset
        )
        apply(&issue)
        return IssueVersion(date: t0 + offset, issue: issue)
    }

    @Test("consecutive versions become one entry per field that changed, newest first")
    func diffs() {
        let versions = [
            version(0) { _ in },
            version(60) { $0.status = "in_progress" },
            version(120) {
                $0.status = "in_progress"
                $0.priority = 1
                $0.assignee = "Ada"
            },
        ]
        let events = History.events(from: versions, activity: .empty)
        #expect(events.map(\.field) == ["priority", "assignee", "status", "created"], "newest first; within a commit, the order fields are listed in")
        #expect(events.first?.date == t0 + 120)
        let status = try! #require(events.first { $0.field == "status" })
        #expect(status.from == "open")
        #expect(status.to == "in_progress")
        let assignee = try! #require(events.first { $0.field == "assignee" })
        #expect(assignee.from == "", "unassigned reads as empty, not nil")
        #expect(assignee.to == "Ada")
    }

    @Test("the first version is the bead being created")
    func creation() {
        let events = History.events(from: [version(0) { _ in }], activity: .empty)
        #expect(events.map(\.field) == ["created"])
        #expect(events.first?.to == "Tile cache")
    }

    @Test("the actor comes from the interaction log, since bd history says root for everyone")
    func actors() {
        let versions = [version(0) { _ in }, version(60) { $0.status = "in_progress" }]
        let log = ActivityLog(entries: [
            ActivityEntry(issueID: "a", actor: "agent-tiles", date: t0 + 61, field: "status"),
        ])
        let events = History.events(from: versions, activity: log)
        #expect(events.first?.actor == "agent-tiles")
        #expect(History.events(from: versions, activity: .empty).first?.actor == nil, "unknown, not invented")
    }

    @Test("a change with no matching log entry doesn't borrow another one's actor")
    func noBorrowing() {
        let versions = [version(0) { _ in }, version(600) { $0.priority = 0 }]
        let log = ActivityLog(entries: [
            ActivityEntry(issueID: "a", actor: "Ada", date: t0 + 60, field: "status"),
            ActivityEntry(issueID: "b", actor: "Ravi", date: t0 + 600, field: "priority"),
        ])
        #expect(History.events(from: versions, activity: log).first?.actor == nil)
    }
}
