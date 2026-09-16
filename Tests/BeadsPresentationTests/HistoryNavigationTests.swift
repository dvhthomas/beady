import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Stepping back to where you were")
struct HistoryNavigationTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("a", title: "Tile cache"),
            makeIssue("b", title: "Download queue", status: "in_progress"),
            makeIssue("c", title: "Stale tiles"),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return model
    }

    @Test("nothing to go back to before you've been anywhere")
    func empty() async {
        let model = await makeModel()
        #expect(!model.canGoBack)
        #expect(!model.canGoForward)
        model.goBack()
        #expect(model.selection == nil, "and going back anyway does nothing")
    }

    @Test("following a link and coming back")
    func backAndForward() async {
        let model = await makeModel()
        model.selection = "a"
        model.selection = "b"   // as if a blocker link was followed
        #expect(model.canGoBack)

        model.goBack()
        #expect(model.selection == "a")
        #expect(model.canGoForward)

        model.goForward()
        #expect(model.selection == "b")
        #expect(!model.canGoForward)
    }

    @Test("the view you were in comes back too, not just the bead")
    func viewsAreRemembered() async {
        let model = await makeModel()
        model.source = .lifecycle(.open)
        model.selection = "a"
        model.source = .lifecycle(.inFlight)
        model.selection = "b"

        // One step at a time, as a browser does: first back to the bead you had selected in
        // In Flight, then back to the view you were in before that.
        model.goBack()
        #expect(model.selection == "a")
        #expect(model.source == .lifecycle(.inFlight))

        model.goBack()
        #expect(model.selection == "a")
        #expect(model.source == .lifecycle(.open))
    }

    @Test("going somewhere new after stepping back drops what was ahead")
    func newBranch() async {
        let model = await makeModel()
        model.selection = "a"
        model.selection = "b"
        model.goBack()
        model.selection = "c"
        #expect(!model.canGoForward)
        model.goBack()
        #expect(model.selection == "a")
    }

    @Test("selecting the same bead twice isn't two steps")
    func noDuplicates() async {
        let model = await makeModel()
        model.selection = "a"
        model.selection = "a"
        model.selection = "b"
        model.goBack()
        #expect(model.selection == "a")
        model.goBack()
        #expect(!model.canGoBack, "one step per place, however many times it was set")
    }

    @Test("history doesn't grow without limit")
    func bounded() async {
        let model = await makeModel()
        for index in 0..<500 {
            model.selection = IssueID(index.isMultiple(of: 2) ? "a" : "b")
        }
        #expect(model.historyDepth <= WorkspaceModel.maxHistory)
    }
}
