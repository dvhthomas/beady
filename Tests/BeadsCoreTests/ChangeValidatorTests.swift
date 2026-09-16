import BeadsCore
import Foundation
import Testing

@Suite("Change validation")
struct ChangeValidatorTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("epic", type: "epic"),
        makeIssue("epic.1", description: "keep me", notes: "notes", parent: "epic"),
        makeIssue("epic.1.1", parent: "epic.1"),
        makeIssue("other", type: "epic"),
        makeIssue("done-epic", status: "closed", type: "epic", closed: t0),
        makeIssue("pinned", status: "pinned"),
    ])

    func codes(_ change: IssueChange) -> [ChangeProblem.Code] {
        ChangeValidator.problems(for: change, in: snapshot).map(\.code)
    }

    func errors(_ change: IssueChange) -> [ChangeProblem.Code] {
        ChangeValidator.problems(for: change, in: snapshot).filter { $0.severity == .error }.map(\.code)
    }

    @Test("edits need a real, non-blank change to an issue that exists")
    func editBasics() {
        #expect(errors(.edit("epic.1", IssueEdit(title: "   "))) == [.emptyTitle])
        #expect(errors(.edit("epic.1", IssueEdit(title: String(repeating: "x", count: 501)))) == [.titleTooLong])
        #expect(errors(.edit("epic.1", IssueEdit(priority: 7))) == [.invalidPriority])
        #expect(errors(.edit("epic.1", IssueEdit(title: "Issue epic.1"))) == [.noChange])
        #expect(errors(.edit("epic.1", IssueEdit())) == [.noChange])
        #expect(errors(.edit("ghost", IssueEdit(title: "x"))) == [.unknownIssue])
        #expect(codes(.edit("epic.1", IssueEdit(title: "New title"))).isEmpty)
    }

    @Test("titles are one line")
    func titleLineBreaks() {
        #expect(errors(.edit("epic.1", IssueEdit(title: "two\nlines"))) == [.titleHasLineBreaks])
        #expect(errors(.create(NewIssue(title: "tab\tand\rreturn"))) == [.titleHasLineBreaks])
    }

    @Test("titles are trimmed, but descriptions and notes are written exactly as typed")
    func normalization() {
        #expect(errors(.edit("epic.1", IssueEdit(title: "  Issue epic.1 \n"))) == [.noChange])
        let normalized = IssueChange.edit("epic.1", IssueEdit(title: "  Tidy  ", description: "    indented code\n", notes: " n \n")).normalized()
        #expect(normalized == .edit("epic.1", IssueEdit(title: "Tidy", description: "    indented code\n", notes: " n \n")))
        #expect(IssueChange.edit("epic.1", IssueEdit(notes: "  \n ")).normalized() == .edit("epic.1", IssueEdit(notes: "")))
        #expect(errors(.edit("epic.1", IssueEdit(description: "keep me\n"))) == [.noChange], "surrounding whitespace alone isn't a change")
    }

    @Test("clearing text that exists is allowed but flagged")
    func clearingWarns() {
        #expect(codes(.edit("epic.1", IssueEdit(description: ""))) == [.clearsDescription])
        #expect(codes(.edit("epic.1", IssueEdit(notes: " "))) == [.clearsNotes])
        #expect(ChangeValidator.problems(for: .edit("epic.1", IssueEdit(description: "")), in: snapshot)
            .allSatisfy { $0.severity == .warning })
    }

    @Test("status must be one the database knows, and different from the current one")
    func statusRules() {
        #expect(errors(.setStatus("epic.1", from: "open", to: "bogus", reason: nil)) == [.unknownStatus])
        #expect(errors(.setStatus("epic.1", from: "open", to: "open", reason: nil)) == [.noChange])
        #expect(codes(.setStatus("epic.1", from: "open", to: "in_progress", reason: nil)).isEmpty)
    }

    @Test("closing needs a reason, so verification can tell our close from anyone else's")
    func closeNeedsReason() {
        #expect(errors(.setStatus("epic.1.1", from: "open", to: "closed", reason: nil)) == [.missingCloseReason])
        #expect(errors(.setStatus("epic.1.1", from: "open", to: "closed", reason: "   ")) == [.missingCloseReason])
        #expect(codes(.setStatus("epic.1.1", from: "open", to: "closed", reason: "shipped")).isEmpty)
    }

    @Test("bd refuses to close an epic with unfinished children; for other issues it's a warning")
    func closingWithOpenChildren() {
        #expect(errors(.setStatus("epic", from: "open", to: "closed", reason: "done")) == [.closesWithOpenChildren])
        let task = ChangeValidator.problems(for: .setStatus("epic.1", from: "open", to: "closed", reason: "done"), in: snapshot)
        #expect(task.map(\.code) == [.closesWithOpenChildren])
        #expect(task.allSatisfy { $0.severity == .warning })
    }

    @Test("bd refuses to close pinned issues")
    func closingPinned() {
        #expect(errors(.setStatus("pinned", from: "pinned", to: "closed", reason: "done")) == [.closesPinned])
    }

    @Test("reparenting can't create a cycle, target self, or point at nothing")
    func parentRules() {
        #expect(errors(.setParent("epic", from: nil, to: "epic.1.1")) == [.parentIsDescendant])
        #expect(errors(.setParent("epic.1", from: "epic", to: "epic.1")) == [.parentIsSelf])
        #expect(errors(.setParent("epic.1", from: "epic", to: "ghost")) == [.unknownParent])
        #expect(errors(.setParent("epic.1", from: "epic", to: "epic")) == [.noChange])
        #expect(codes(.setParent("epic.1", from: "epic", to: "other")).isEmpty)
        #expect(codes(.setParent("epic.1", from: "epic", to: nil)).isEmpty)
        #expect(codes(.setParent("epic.1", from: "epic", to: "done-epic")) == [.closedParent])
    }

    @Test("new beads need a title, a known type, a valid priority and a real parent")
    func createRules() {
        #expect(errors(.create(NewIssue(title: " "))) == [.emptyTitle])
        #expect(errors(.create(NewIssue(title: "x", type: "banana"))) == [.invalidType])
        #expect(errors(.create(NewIssue(title: "x", priority: -1))) == [.invalidPriority])
        #expect(errors(.create(NewIssue(title: "x", parent: "ghost"))) == [.unknownParent])
        #expect(codes(.create(NewIssue(title: "x", parent: "done-epic"))) == [.closedParent])
        #expect(codes(.create(NewIssue(title: "Fresh", type: "bug", priority: 1, parent: "epic"))).isEmpty)
    }

    @Test("each lifecycle column has a status to drop into")
    func defaultStatuses() {
        #expect(StatusCategory.active.defaultStatus == "open")
        #expect(StatusCategory.wip.defaultStatus == "in_progress")
        #expect(StatusCategory.frozen.defaultStatus == "deferred")
        #expect(StatusCategory.done.defaultStatus == "closed")
    }
}

@Suite("Change conflicts and verification")
struct ChangeGuardTests {
    let seen = makeIssue("a", description: "d", notes: "n", parent: "epic", updated: t0)

    @Test("a field being edited that changed since it was seen is a conflict")
    func touchedFieldConflict() {
        var current = seen
        current.title = "Someone else's title"
        current.updatedAt = t0 + 5
        let conflicts = ChangeGuard.conflicts(for: .edit("a", IssueEdit(title: "Mine")), seen: seen, current: current)
        #expect(conflicts.map(\.field) == ["title"])
    }

    @Test("changes to fields this edit doesn't touch are not conflicts")
    func untouchedFieldIsFine() {
        var current = seen
        current.notes = "someone appended notes"
        current.updatedAt = t0 + 5
        #expect(ChangeGuard.conflicts(for: .edit("a", IssueEdit(title: "Mine")), seen: seen, current: current).isEmpty)
    }

    @Test("status and parent moves conflict when those moved meanwhile")
    func statusAndParentConflicts() {
        var current = seen
        current.status = "in_progress"
        current.parentID = "other"
        #expect(ChangeGuard.conflicts(for: .setStatus("a", from: "open", to: "closed", reason: nil), seen: seen, current: current)
            .map(\.field) == ["status"])
        #expect(ChangeGuard.conflicts(for: .setParent("a", from: "epic", to: nil), seen: seen, current: current)
            .map(\.field) == ["parent"])
    }

    @Test("untouched differences are the fields a change doesn't touch that differ")
    func untouchedDifferences() {
        var after = seen
        after.parentID = "other"
        after.notes = "someone else"
        #expect(ChangeGuard.untouchedDifferences(for: .setParent("a", from: "epic", to: "other"), before: seen, after: after)
            .map(\.field) == ["notes"])
    }

    @Test("verification reports every intended field that didn't land")
    func mismatches() {
        var after = seen
        after.title = "Mine"
        let edit = IssueChange.edit("a", IssueEdit(title: "Mine", notes: "new notes"))
        #expect(ChangeGuard.mismatches(for: edit, after: after).map(\.field) == ["notes"])
        #expect(ChangeGuard.mismatches(for: .setStatus("a", from: "open", to: "closed", reason: "x"), after: after)
            .map(\.field) == ["status", "close reason"])
    }

    @Test("a close only verifies if our reason is the one stored")
    func closeReasonVerified() {
        var closedByAgent = seen
        closedByAgent.status = "closed"
        closedByAgent.closedAt = t0
        closedByAgent.closeReason = "duplicate, do not ship"
        #expect(ChangeGuard.mismatches(for: .setStatus("a", from: "open", to: "closed", reason: "shipped"), after: closedByAgent)
            .map(\.field) == ["close reason"])
    }

    @Test("a reopen only verifies once the closed time is gone")
    func reopenClearsClosedAt() {
        var stillStamped = seen
        stillStamped.status = "open"
        stillStamped.closedAt = t0
        #expect(ChangeGuard.mismatches(for: .setStatus("a", from: "closed", to: "open", reason: nil), after: stillStamped)
            .map(\.field) == ["closed at"])
    }

    @Test("descriptions and notes must land exactly, whitespace included")
    func exactText() {
        var after = seen
        after.description = "code"
        #expect(ChangeGuard.mismatches(for: .edit("a", IssueEdit(description: "    code")), after: after).map(\.field) == ["description"])
    }
}
