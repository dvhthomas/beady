import BeadsCore
import Foundation
import Testing

@Suite("Editing the fields bd can set")
struct EditFieldsTests {
    let snapshot = IssueSnapshot(issues: [
        makeIssue("a", title: "Tile cache", type: "task", assignee: "Ada", labels: ["offline", "tiles"]),
        makeIssue("b", title: "Other", type: "bug"),
    ])

    func edit(_ apply: (inout IssueEdit) -> Void) -> IssueChange {
        var edit = IssueEdit()
        apply(&edit)
        return .edit("a", edit)
    }

    @Test("an empty edit is still nothing to do")
    func empty() {
        #expect(IssueEdit().isEmpty)
        #expect(!IssueEdit(assignee: "Ravi").isEmpty)
        #expect(!IssueEdit(addedLabels: ["urgent"]).isEmpty)
    }

    @Test("type has to be one this database knows")
    func types() {
        let unknown = ChangeValidator.problems(for: edit { $0.type = "invention" }, in: snapshot)
        #expect(unknown.map(\.code) == [.invalidType])
        #expect(ChangeValidator.problems(for: edit { $0.type = "bug" }, in: snapshot).isEmpty)
        #expect(ChangeValidator.problems(for: edit { $0.type = "task" }, in: snapshot).map(\.code) == [.noChange])
    }

    @Test("an assignee is one line, and can be cleared")
    func assignee() {
        #expect(ChangeValidator.problems(for: edit { $0.assignee = "Ravi" }, in: snapshot).isEmpty)
        #expect(ChangeValidator.problems(for: edit { $0.assignee = "" }, in: snapshot).isEmpty, "clearing is allowed")
        let broken = ChangeValidator.problems(for: edit { $0.assignee = "Ada\nRavi" }, in: snapshot)
        #expect(broken.map(\.code) == [.assigneeHasLineBreaks])
    }

    @Test("labels go on and come off, and bd has to be able to carry them")
    func labels() {
        #expect(ChangeValidator.problems(for: edit { $0.addedLabels = ["urgent"] }, in: snapshot).isEmpty)
        #expect(ChangeValidator.problems(for: edit { $0.removedLabels = ["offline"] }, in: snapshot).isEmpty)

        let already = ChangeValidator.problems(for: edit { $0.addedLabels = ["offline"] }, in: snapshot)
        #expect(already.map(\.code) == [.noChange], "it already has that label")

        let missing = ChangeValidator.problems(for: edit { $0.removedLabels = ["nope"] }, in: snapshot)
        #expect(missing.map(\.code) == [.noChange])

        let contradiction = ChangeValidator.problems(for: edit {
            $0.addedLabels = ["urgent"]
            $0.removedLabels = ["urgent"]
        }, in: snapshot)
        #expect(contradiction.map(\.code) == [.contradictoryLabels])

        let comma = ChangeValidator.problems(for: edit { $0.addedLabels = ["needs, care"] }, in: snapshot)
        #expect(comma.map(\.code) == [.unusableLabel], "bd splits label lists on commas")
    }

    @Test("normalising trims what should be trimmed and drops empty labels")
    func normalising() {
        let change = edit {
            $0.type = "  bug  "
            $0.assignee = "  Ravi  "
            $0.addedLabels = ["  urgent  ", "   "]
        }
        guard case .edit(_, let normalized) = change.normalized() else {
            Testing.Issue.record("expected an edit")
            return
        }
        #expect(normalized.type == "bug")
        #expect(normalized.assignee == "Ravi")
        #expect(normalized.addedLabels == ["urgent"])
    }

    @Test("the write is checked by reading the bead back")
    func verification() {
        var after = snapshot.issue("a")!
        after.type = "bug"
        after.assignee = "Ravi"
        after.labels = ["tiles", "urgent"]
        let change = edit {
            $0.type = "bug"
            $0.assignee = "Ravi"
            $0.addedLabels = ["urgent"]
            $0.removedLabels = ["offline"]
        }
        #expect(ChangeGuard.mismatches(for: change.normalized(), after: after).isEmpty)

        var wrong = after
        wrong.labels = ["tiles", "urgent", "offline"]
        let failures = ChangeGuard.mismatches(for: change.normalized(), after: wrong)
        #expect(failures.contains { $0.field.contains("offline") }, "a label that didn't come off is a failed write")
    }
}
