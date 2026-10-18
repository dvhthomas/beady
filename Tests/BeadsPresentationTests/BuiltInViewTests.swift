import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// Each built-in is checked against what the lifecycle scope it replaces used to show, on the
/// fixture the old Scope tests used.
@Suite("Built-in views")
struct BuiltInViewTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("open-free"),
        makeIssue("open-blocked", blockedBy: ["wip"]),
        makeIssue("wip", status: "in_progress"),
        makeIssue("frozen", status: "deferred"),
        makeIssue("done", status: "closed", closed: t0),
        makeIssue("later", deferUntil: t0 + days(1)),
    ])

    func ids(_ id: IssueView.ID, in snapshot: IssueSnapshot? = nil, now: Date = t0) -> Set<IssueID> {
        let snapshot = snapshot ?? self.snapshot
        let view = IssueView.builtIn(id)!
        return Set(snapshot.issues.filter { view.filter.matches($0, in: snapshot, now: now) }.map(\.id))
    }

    @Test("Frontier shows what Ready did: active, not blocked, not deferred into the future")
    func frontier() {
        #expect(ids(.frontier) == ["open-free"])
    }

    @Test("In Flight shows what In Flight did: the wip category")
    func inFlight() {
        #expect(ids(.inFlight) == ["wip"])
    }

    @Test("Stuck shows what Blocked did")
    func stuck() {
        #expect(ids(.stuck) == ["open-blocked"])
    }

    @Test("Deferred shows what Deferred did: the frozen category")
    func deferred() {
        #expect(ids(.deferred) == ["frozen"])
    }

    @Test("Landed shows what Closed did, for a week")
    func landed() {
        #expect(ids(.landed) == ["done"])
        #expect(ids(.landed, now: t0 + days(8)).isEmpty, "after a week it has landed and gone")
    }

    @Test("Everything shows what All did")
    func everything() {
        #expect(ids(.everything).count == snapshot.issues.count)
    }

    @Test("Pipeline is everything live plus a week of done")
    func pipeline() {
        #expect(ids(.pipeline).count == snapshot.issues.count)
        #expect(ids(.pipeline, now: t0 + days(8)) == ["open-free", "open-blocked", "wip", "frozen", "later"])
    }

    @Test("Recent is what was touched in the last day")
    func recent() {
        #expect(ids(.recent).count == snapshot.issues.count)
        #expect(ids(.recent, now: t0 + days(2)).isEmpty)
    }

    @Test("Starred is the label")
    func starred() {
        let marked = IssueSnapshot(issues: [
            makeIssue("plain"),
            makeIssue("starred", labels: [IssueMark.starred.label]),
            makeIssue("done-starred", status: "closed", labels: [IssueMark.starred.label], closed: t0),
        ])
        #expect(ids(.starred, in: marked) == ["starred", "done-starred"], "whatever its lifecycle")
    }

    @Test("Open and Closed are one Lifecycle chip away from Everything")
    func openAndClosed() {
        var open = IssueView.builtIn(.everything)!.filter
        open.toggle(StatusCategory.active.rawValue, in: .lifecycle)
        #expect(Set(snapshot.issues.filter { open.matches($0, in: snapshot, now: t0) }.map(\.id)) == ["open-free", "open-blocked", "later"])
        var closed = IssueView.builtIn(.everything)!.filter
        closed.toggle(StatusCategory.done.rawValue, in: .lifecycle)
        #expect(Set(snapshot.issues.filter { closed.matches($0, in: snapshot, now: t0) }.map(\.id)) == ["done"])
    }

    @Test("the table: sidebar order, unique ids, every one built in, each with a symbol")
    func table() {
        let views = IssueView.builtIns
        #expect(views.map(\.name) == ["Frontier", "In Flight", "Stuck", "Pipeline", "Recent", "Landed", "Deferred", "Everything", "Starred"])
        #expect(Set(views.map(\.id)).count == views.count)
        #expect(views.allSatisfy { $0.isBuiltIn })
        #expect(views.allSatisfy { !$0.symbol.isEmpty })
        #expect(IssueView.builtIn(.frontier)?.name == "Frontier")
        #expect(IssueView.builtIn(IssueView.ID("nope")) == nil)
    }

    @Test("each built-in remembers how it is shown")
    func presentation() {
        let pipeline = IssueView.builtIn(.pipeline)!.presentation
        #expect(pipeline.layout == .board)
        #expect(pipeline.grouping == .category)
        #expect(pipeline.ordering == .priority)
        #expect(IssueView.builtIn(.recent)?.presentation.grouping == .assignee)
        #expect(IssueView.builtIn(.landed)?.presentation.ordering == .recentlyClosed)
        #expect(IssueView.builtIn(.inFlight)?.presentation.grouping == .status)
        #expect(IssueView.builtIn(.everything)?.presentation.grouping == .category)
        // Blockers matter in Stuck and nowhere much else: on there, off (the default) in Frontier.
        #expect(IssueView.builtIn(.stuck)?.presentation.columns?.contains(ListColumn.blockedBy.id) == true)
        #expect(IssueView.builtIn(.frontier)?.presentation.columns == nil)
        for view in IssueView.builtIns {
            for column in view.presentation.columns ?? [] {
                #expect(ListColumn(rawValue: column) != nil, "\(view.name) names a column that doesn't exist: \(column)")
            }
        }
    }
}
