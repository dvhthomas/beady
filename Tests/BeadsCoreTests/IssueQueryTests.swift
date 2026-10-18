import BeadsCore
import Foundation
import Testing

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
