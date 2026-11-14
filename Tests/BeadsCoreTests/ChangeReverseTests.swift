import BeadsCore
import Testing

@Suite("Reversing a change for Undo")
struct ChangeReverseTests {
    let base = makeIssue(
        "a", title: "Original", description: "Old words", notes: "Old notes",
        status: "open", priority: 2, type: "task", assignee: "pat", labels: ["kept", "lost"]
    )

    @Test("a status move reverses, except back into closed, which bd wants a fresh reason for")
    func statusReverses() {
        let move = IssueChange.setStatus("a", from: "open", to: "in_progress", reason: nil)
        #expect(move.reversed(from: base) == .setStatus("a", from: "in_progress", to: "open", reason: nil))

        let close = IssueChange.setStatus("a", from: "open", to: "closed", reason: "done")
        #expect(close.reversed(from: base) == .setStatus("a", from: "closed", to: "open", reason: nil))

        let reopen = IssueChange.setStatus("a", from: "closed", to: "open", reason: nil)
        #expect(reopen.reversed(from: base) == nil, "its reverse would close without a reason")
    }

    @Test("parent, mark and blocker changes reverse by swapping their direction")
    func graphAndMarksReverse() {
        #expect(IssueChange.setParent("a", from: "p1", to: "p2").reversed(from: base)
            == .setParent("a", from: "p2", to: "p1"))
        #expect(IssueChange.setMark("a", .pinned, on: true).reversed(from: base)
            == .setMark("a", .pinned, on: false))
        #expect(IssueChange.setBlocker("a", blocker: "b", on: false).reversed(from: base)
            == .setBlocker("a", blocker: "b", on: true))
    }

    @Test("an edit reverses to the bead as it was, touching only the fields the edit touched")
    func editReverses() throws {
        let edit = IssueChange.edit("a", IssueEdit(title: "Renamed", priority: 0))
        let reversed = try #require(edit.reversed(from: base))
        #expect(reversed == .edit("a", IssueEdit(title: "Original", priority: 2)))

        let clearAssignee = IssueChange.edit("a", IssueEdit(assignee: ""))
        #expect(clearAssignee.reversed(from: base) == .edit("a", IssueEdit(assignee: "pat")))
    }

    @Test("label edits reverse to what the bead really had")
    func labelsReverse() throws {
        // Added one new, one it already had; removed one it had, one it didn't.
        let edit = IssueChange.edit("a", IssueEdit(
            addedLabels: ["new", "kept"], removedLabels: ["lost", "never"]
        ))
        let reversed = try #require(edit.reversed(from: base))
        #expect(reversed == .edit("a", IssueEdit(addedLabels: ["lost"], removedLabels: ["new"])))
    }

    @Test("creates, and edits with no before-state, have no reverse")
    func irreversibles() {
        #expect(IssueChange.create(NewIssue(title: "x", type: "task", priority: 2, description: "", parent: nil)).reversed(from: nil) == nil)
        #expect(IssueChange.edit("a", IssueEdit(title: "Renamed")).reversed(from: nil) == nil)
        #expect(IssueChange.edit("a", IssueEdit(title: "Renamed")).reversed(from: makeIssue("other")) == nil)
    }
}
