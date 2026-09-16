import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Moving around the board with the keyboard")
struct BoardNavigationTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("a", priority: 0),
            makeIssue("b", priority: 1),
            makeIssue("c", status: "in_progress"),
            makeIssue("d", status: "closed", closed: t0),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        model.source = .lifecycle(.all)
        model.layout = .board
        model.grouping = .category
        model.ordering = .priority
        return model
    }

    @Test("with nothing selected, the first card takes the highlight")
    func firstCard() async {
        let model = await makeModel()
        model.moveSelection(.down)
        #expect(model.selection == "a")
    }

    @Test("up and down move within a column and stop at its ends")
    func withinColumn() async {
        let model = await makeModel()
        model.selection = "a"
        model.moveSelection(.down)
        #expect(model.selection == "b")
        model.moveSelection(.down)
        #expect(model.selection == "b", "the bottom of the column is the bottom")
        model.moveSelection(.up)
        #expect(model.selection == "a")
        model.moveSelection(.up)
        #expect(model.selection == "a")
    }

    @Test("left and right cross columns, keeping your place down the column")
    func acrossColumns() async {
        let model = await makeModel()
        model.selection = "a"
        model.moveSelection(.right)
        #expect(model.selection == "c", "same row in the next column")
        model.moveSelection(.left)
        #expect(model.selection == "a")
        model.moveSelection(.left)
        #expect(model.selection == "a", "the first column is the first column")

        model.selection = "b"
        model.moveSelection(.right)
        #expect(model.selection == "c", "a shorter column lands you on its last card")
    }

    @Test("moving only applies to the board; the list and tree have their own")
    func boardOnly() async {
        let model = await makeModel()
        model.layout = .list
        model.selection = "a"
        model.moveSelection(.right)
        #expect(model.selection == "a")
    }
}
