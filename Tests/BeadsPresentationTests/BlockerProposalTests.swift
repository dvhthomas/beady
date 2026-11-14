import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Which beads are offered as blockers")
struct BlockerChoiceTests {
    /// `bead` already waits for `already`; `loop-direct` waits for `bead`, and `loop-far` waits
    /// for `loop-direct`, so making `bead` wait for either would leave them all stuck.
    func makeModel() async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore([
            makeIssue("bead", blockedBy: ["already"]),
            makeIssue("already"),
            makeIssue("finished", status: "closed", closed: t0),
            makeIssue("loop-direct", blockedBy: ["bead"]),
            makeIssue("loop-far", blockedBy: ["loop-direct"]),
            makeIssue("zz-open"),
            makeIssue("aa-open"),
        ]), now: { t0 })
        await model.load()
        return model
    }

    @Test("itself, its blockers, finished beads and anything that would loop are out; open beads are in, by id")
    func choices() async {
        let model = await makeModel()
        #expect(model.blockerChoices(for: "bead").map(\.id) == ["aa-open", "zz-open"])
    }

    @Test("the loop check walks the whole chain, not just the first hop")
    func transitiveLoop() async {
        let model = await makeModel()
        let choices = model.blockerChoices(for: "bead").map(\.id)
        #expect(!choices.contains("loop-direct"), "it waits for bead directly")
        #expect(!choices.contains("loop-far"), "it waits for bead through loop-direct")
    }

    @Test("a bead nothing waits for is offered everything open, sorted by id")
    func ordinaryBead() async {
        let model = await makeModel()
        #expect(model.blockerChoices(for: "zz-open").map(\.id) == ["aa-open", "already", "bead", "loop-direct", "loop-far"])
    }

    @Test("a bead the snapshot doesn't know gets no choices")
    func unknownBead() async {
        let model = await makeModel()
        #expect(model.blockerChoices(for: "ghost").isEmpty)
    }
}

@MainActor
@Suite("Proposing a blocker stages a readable pending change")
struct BlockerProposalTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        let store = MemoryStore([
            makeIssue("a", blockedBy: ["b"]),
            makeIssue("b"),
            makeIssue("plain"),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return (model, store)
    }

    @Test("adding a blocker names both beads and writes nothing until confirmed")
    func proposeOn() async throws {
        let (model, store) = await makeModel()
        model.proposeBlocker("plain", blocker: "b", on: true)
        let pending = try #require(model.pendingChange)
        #expect(pending.change == .setBlocker("plain", blocker: "b", on: true))
        #expect(pending.summary == "Make plain wait for b")
        #expect(pending.subject == "plain · Issue plain")
        #expect(pending.details == ["Blocked by: add b “Issue b”"])
        #expect(pending.problems.isEmpty)
        #expect(pending.canConfirm)
        #expect(store.applied.isEmpty, "staged, not written")
    }

    @Test("removing a blocker reads as stopping the wait")
    func proposeOff() async throws {
        let (model, _) = await makeModel()
        model.proposeBlocker("a", blocker: "b", on: false)
        let pending = try #require(model.pendingChange)
        #expect(pending.change == .setBlocker("a", blocker: "b", on: false))
        #expect(pending.summary == "Stop a waiting for b")
        #expect(pending.subject == "a · Issue a")
        #expect(pending.details == ["Blocked by: remove b “Issue b”"])
        #expect(pending.problems.isEmpty)
        #expect(pending.canConfirm)
    }
}

@MainActor
@Suite("Proposing a parent move directly, not via a board drop")
struct ParentProposalTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        let store = MemoryStore([
            makeIssue("epic", type: "epic"),
            makeIssue("epic.1", parent: "epic"),
            makeIssue("other", type: "epic"),
            makeIssue("plain"),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return (model, store)
    }

    @Test("the current parent rides along as the change's `from`")
    func moveCarriesCurrentParent() async throws {
        let (model, _) = await makeModel()
        model.proposeParent("epic.1", to: "other")
        let pending = try #require(model.pendingChange)
        #expect(pending.change == .setParent("epic.1", from: "epic", to: "other"))
        #expect(pending.summary == "Move epic.1 to other")
        #expect(pending.canConfirm)
    }

    @Test("a nil parent clears: 'Remove X from Y', with the old parent named in the details")
    func clearNamesTheOldParent() async throws {
        let (model, _) = await makeModel()
        model.proposeParent("epic.1", to: nil)
        let pending = try #require(model.pendingChange)
        #expect(pending.change == .setParent("epic.1", from: "epic", to: nil))
        #expect(pending.summary == "Remove epic.1 from epic")
        #expect(pending.details == ["Parent: epic “Issue epic” → none"])
        #expect(pending.canConfirm)
    }

    @Test("clearing a bead with no parent reads 'from its parent' and can't be applied")
    func clearWithNoParent() async throws {
        let (model, _) = await makeModel()
        model.proposeParent("plain", to: nil)
        let pending = try #require(model.pendingChange)
        #expect(pending.change == .setParent("plain", from: nil, to: nil))
        #expect(pending.summary == "Remove plain from its parent")
        #expect(!pending.canConfirm, "nothing would change")
    }

    @Test("a bead the snapshot doesn't know stages nothing")
    func unknownBead() async {
        let (model, _) = await makeModel()
        model.proposeParent("ghost", to: "epic")
        #expect(model.pendingChange == nil)
    }
}

@MainActor
@Suite("The confirmation sheet's text for edits and marks")
struct ChangeDescriptionTests {
    func makeModel() async -> (WorkspaceModel, MemoryStore) {
        var texty = makeIssue("texty")
        texty.description = "0123456789"
        texty.notes = "ten chars!"
        let store = MemoryStore([texty, makeIssue("plain")])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return (model, store)
    }

    func details(_ model: WorkspaceModel, _ change: IssueChange) -> [String] {
        model.propose(change)
        defer { model.cancelPendingChange() }
        return model.pendingChange?.details ?? []
    }

    @Test("clearing a description says how much is going, and warns")
    func cleared() async throws {
        let (model, _) = await makeModel()
        model.propose(.edit("texty", IssueEdit(description: "")))
        let pending = try #require(model.pendingChange)
        #expect(pending.details == ["Description: cleared (was 10 characters)"])
        #expect(pending.problems.map(\.code) == [.clearsDescription])
    }

    @Test("adding text says how much arrived; a resize counts both ends")
    func addedAndResized() async {
        let (model, _) = await makeModel()
        #expect(details(model, .edit("plain", IssueEdit(description: "hello"))) == ["Description: added (5 characters)"])
        #expect(details(model, .edit("texty", IssueEdit(description: "wxyz"))) == ["Description: 10 → 4 characters"])
    }

    @Test("notes take the same three shapes, under their own name")
    func notes() async {
        let (model, _) = await makeModel()
        #expect(details(model, .edit("texty", IssueEdit(notes: ""))) == ["Notes: cleared (was 10 characters)"])
        #expect(details(model, .edit("plain", IssueEdit(notes: "abcd"))) == ["Notes: added (4 characters)"])
        #expect(details(model, .edit("texty", IssueEdit(notes: "no"))) == ["Notes: 10 → 2 characters"])
    }

    @Test("a mark reads as the bd label it adds or removes")
    func markDetails() async throws {
        let (model, _) = await makeModel()
        model.propose(.setMark("plain", .pinned, on: true))
        var pending = try #require(model.pendingChange)
        #expect(pending.summary == "Pin plain")
        #expect(pending.details == ["Label: add “pinned”"])
        model.cancelPendingChange()

        model.propose(.setMark("texty", .starred, on: false))
        pending = try #require(model.pendingChange)
        #expect(pending.summary == "Unstar texty")
        #expect(pending.details == ["Label: remove “starred”"])
    }
}
