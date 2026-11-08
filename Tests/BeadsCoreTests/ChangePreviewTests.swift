import BeadsCore
import Testing

@Suite("Previewing a change before bd confirms it")
struct ChangePreviewTests {
    let base = makeIssue(
        "a", title: "Original", status: "open", priority: 2,
        assignee: "pat", labels: ["kept"], parent: "p1"
    )

    @Test("a status move previews as the new status")
    func statusPreview() throws {
        let preview = try #require(IssueChange.setStatus("a", from: "open", to: "in_progress", reason: nil).applied(to: base))
        #expect(preview.status == "in_progress")
        #expect(preview.title == base.title, "nothing else moves")
    }

    @Test("a parent move previews as the new parent")
    func parentPreview() throws {
        let preview = try #require(IssueChange.setParent("a", from: "p1", to: "p2").applied(to: base))
        #expect(preview.parentID == "p2")
        let orphaned = try #require(IssueChange.setParent("a", from: "p1", to: nil).applied(to: base))
        #expect(orphaned.parentID == nil)
    }

    @Test("an edit previews its fields, including labels and a cleared assignee")
    func editPreview() throws {
        let preview = try #require(IssueChange.edit("a", IssueEdit(
            title: "Renamed", priority: 0, assignee: "",
            addedLabels: ["new"], removedLabels: ["kept"]
        )).applied(to: base))
        #expect(preview.title == "Renamed")
        #expect(preview.priority == 0)
        #expect(preview.assignee == nil)
        #expect(Set(preview.labels) == ["new"])
    }

    @Test("a mark previews as its label, on or off")
    func markPreview() throws {
        let marked = try #require(IssueChange.setMark("a", .pinned, on: true).applied(to: base))
        #expect(marked.has(.pinned))
        let unmarked = try #require(IssueChange.setMark("a", .pinned, on: false).applied(to: marked))
        #expect(!unmarked.has(.pinned))
    }

    @Test("creates, blocker changes and the wrong bead have no one-issue preview")
    func noPreview() {
        #expect(IssueChange.create(NewIssue(title: "x", type: "task", priority: 2, description: "", parent: nil)).applied(to: base) == nil)
        #expect(IssueChange.setBlocker("a", blocker: "b", on: true).applied(to: base) == nil)
        #expect(IssueChange.setStatus("other", from: "open", to: "closed", reason: nil).applied(to: base) == nil)
    }
}
