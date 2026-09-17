import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("The edit draft")
struct EditDraftTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("a", title: "Tile cache", type: "task", assignee: "Ada", labels: ["offline", "tiles"]),
            makeIssue("b", title: "Search", type: "bug", assignee: "Ravi", labels: ["search"]),
            makeIssue("epic", title: "Offline maps", type: "epic"),
            makeIssue("epic.1", title: "Child", parent: "epic"),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return model
    }

    @Test("a fresh draft matches the bead and has nothing to save")
    func fresh() async {
        let model = await makeModel()
        let draft = try! #require(model.editDraft(for: "a"))
        #expect(draft.title == "Tile cache")
        #expect(draft.type == "task")
        #expect(draft.assignee == "Ada")
        #expect(draft.labels == ["offline", "tiles"])
        #expect(!draft.hasChanges)
        #expect(draft.change == nil)
    }

    @Test("only what changed is sent")
    func minimalChange() async {
        let model = await makeModel()
        var draft = try! #require(model.editDraft(for: "a"))
        draft.assignee = "Ravi"
        let change = try! #require(draft.change)
        guard case .edit(let id, let edit) = change else {
            Testing.Issue.record("expected an edit")
            return
        }
        #expect(id == "a")
        #expect(edit.assignee == "Ravi")
        #expect(edit.title == nil, "an untouched title isn't part of the change")
        #expect(edit.addedLabels.isEmpty && edit.removedLabels.isEmpty)
    }

    @Test("labels become adds and removes, which is how bd writes them")
    func labels() async {
        let model = await makeModel()
        var draft = try! #require(model.editDraft(for: "a"))
        draft.labels = ["tiles", "urgent"]
        guard case .edit(_, let edit)? = draft.change else {
            Testing.Issue.record("expected an edit")
            return
        }
        #expect(edit.addedLabels == ["urgent"])
        #expect(edit.removedLabels == ["offline"])
    }

    @Test("clearing the assignee is a change, not a no-op")
    func clearing() async {
        let model = await makeModel()
        var draft = try! #require(model.editDraft(for: "a"))
        draft.assignee = ""
        guard case .edit(_, let edit)? = draft.change else {
            Testing.Issue.record("expected an edit")
            return
        }
        #expect(edit.assignee == "")
    }

    @Test("the form's vocabulary comes from the database, not from a hard-coded list")
    func vocabulary() async {
        let model = await makeModel()
        #expect(model.knownAssignees == ["Ada", "Ravi"])
        #expect(model.knownLabels == ["offline", "search", "tiles"])
        #expect(model.knownTypes.contains("epic") && model.knownTypes.contains("task"))
        #expect(model.knownTypes == model.knownTypes.sorted(), "listed in a stable order")
        #expect(model.knownStatuses.contains("open"), "statuses come from bd's own catalogue")
    }

    @Test("a draft for a bead that isn't there is nothing at all")
    func missing() async {
        let model = await makeModel()
        #expect(model.editDraft(for: "nope") == nil)
    }
}

@MainActor
@Suite("Editing through the model")
struct EditingSessionTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        let store = MemoryStore([
            makeIssue("a", title: "Tile cache", type: "task", assignee: "Ada", labels: ["offline"]),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return (model, store)
    }

    @Test("editing starts from the bead and ends when asked")
    func lifecycle() async {
        let (model, _) = await makeModel()
        #expect(model.draft == nil)
        model.beginEditing("a")
        #expect(model.draft?.title == "Tile cache")
        model.endEditing()
        #expect(model.draft == nil)
    }

    @Test("reviewing a draft proposes only what changed, and nothing is written yet")
    func review() async {
        let (model, store) = await makeModel()
        model.beginEditing("a")
        model.draft?.assignee = "Ravi"
        model.draft?.labels = ["offline", "urgent"]
        model.reviewDraft()

        let pending = try! #require(model.pendingChange)
        guard case .edit(_, let edit) = pending.change else {
            Testing.Issue.record("expected an edit")
            return
        }
        #expect(edit.assignee == "Ravi")
        #expect(edit.addedLabels == ["urgent"])
        #expect(edit.title == nil)
        #expect(store.applied.isEmpty, "the sheet is still the gate")
    }

    @Test("a draft with nothing in it proposes nothing")
    func unchanged() async {
        let (model, _) = await makeModel()
        model.beginEditing("a")
        model.reviewDraft()
        #expect(model.pendingChange == nil)
    }

    @Test("a refresh underneath doesn't rewrite what someone is typing")
    func refreshDoesntClobber() async {
        let (model, store) = await makeModel()
        model.beginEditing("a")
        model.draft?.title = "Tile cache, rewritten"
        store.setTitle("a", "Changed by someone else")
        await model.load()
        #expect(model.draft?.title == "Tile cache, rewritten")
        #expect(model.draft?.original.title == "Tile cache", "and the comparison still uses what they started from")
    }

    @Test("a read-only workspace can't start editing")
    func readOnly() async {
        let model = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a")]), allowsWriting: false, now: { t0 })
        await model.load()
        model.beginEditing("a")
        #expect(model.draft == nil)
    }
}

@MainActor
@Suite("Backup, as the window reports it")
struct BackupSummaryTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        let store = MemoryStore([makeIssue("a")])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 + 3600 })
        await model.load()
        return (model, store)
    }

    @Test("a database with no backup says so, and the palette offers to set one up")
    func notConfigured() async {
        let (model, _) = await makeModel()
        #expect(model.backupSummary == "not backed up")
        #expect(CommandCatalog.results(for: "", model: model).contains(.setUpBackup))
        #expect(!CommandCatalog.results(for: "", model: model).contains(.backUpNow))
    }

    @Test("setting one up runs the first backup and changes what's offered")
    func setUp() async {
        let (model, _) = await makeModel()
        let failure = await model.startBackingUp(to: "/tmp/backups")
        #expect(failure == nil)
        #expect(model.backup.destination == "/tmp/backups")
        #expect(model.backupSummary == "backed up 1 hour ago")
        #expect(CommandCatalog.results(for: "", model: model).contains(.backUpNow))
    }

    @Test("a backup that fails says why rather than pretending")
    func failure() async {
        let (model, store) = await makeModel()
        store.backup = BackupStatus(destination: "/tmp/backups", lastSync: nil, databaseSize: "1 KB")
        await model.refreshBackupStatus()
        #expect(model.backupSummary == "backup set up, not run yet")

        store.failure = LoadFailure()
        let failure = await model.backUpNow()
        #expect(failure == "bd exploded")
    }
}
