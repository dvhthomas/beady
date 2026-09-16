import BeadsCore
import Foundation
import Testing

@Suite("Pins and stars, carried by bd labels")
struct MarkTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("plain", priority: 2),
        makeIssue("pinned", priority: 3, labels: ["pinned"]),
        makeIssue("starred", priority: 1, labels: ["starred", "search"]),
        makeIssue("both", priority: 4, labels: ["pinned", "starred"]),
    ])

    @Test("a mark is just a bd label, named in one place")
    func marksAreLabels() {
        #expect(IssueMark.pinned.label == "pinned")
        #expect(IssueMark.starred.label == "starred")
        #expect(IssueMark.allCases.count == 2)
        #expect(snapshot.issue("pinned")!.has(.pinned))
        #expect(!snapshot.issue("pinned")!.has(.starred))
        #expect(snapshot.issue("both")!.has(.starred))
    }

    @Test("pinned beads float to the top of any ordering, keeping that ordering among themselves")
    func pinnedFirst() {
        let sorted = IssueSort.priority.sorted(snapshot.issues, pinnedFirst: true)
        #expect(sorted.map(\.id) == ["pinned", "both", "starred", "plain"], "pinned by priority, then the rest")
        let plain = IssueSort.priority.sorted(snapshot.issues, pinnedFirst: false)
        #expect(plain.map(\.id) == ["starred", "plain", "pinned", "both"])
    }

    @Test("a label is a view of its own, which is what Starred is")
    func labelView() {
        let source = ViewSource.label("starred")
        let now = t0
        #expect(Set(snapshot.issues.filter { source.includes($0, in: snapshot, now: now) }.map(\.id)) == ["starred", "both"])
        #expect(source.categories == Set(StatusCategory.allCases), "a label view spans every lifecycle")
        #expect(!ViewSource.label("starred").includes(snapshot.issue("plain")!, in: snapshot, now: now))
    }

    @Test("grouping keeps pinned beads at the top of each group")
    func groupsKeepPinsFirst() {
        let ordered = IssueSort.priority.sorted(snapshot.issues, pinnedFirst: true)
        let groups = IssueGrouping.none.groups(ordered, in: snapshot, including: [])
        #expect(groups.first?.issues.map(\.id) == ["pinned", "both", "starred", "plain"])
    }
}
