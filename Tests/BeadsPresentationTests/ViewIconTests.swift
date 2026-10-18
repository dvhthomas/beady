import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// Every view has an icon, and it is never the List / Board / Tree glyph: the layout switcher
/// owns those, and a sidebar row should say what the view answers.
@Suite("View icons")
struct ViewIconTests {
    @Test("every built-in has the symbol from the table")
    func builtIns() {
        let expected: [IssueView.ID: String] = [
            .frontier: "play.circle", .inFlight: "circle.lefthalf.filled", .stuck: "hourglass",
            .pipeline: "flowchart", .recent: "clock", .landed: "checkmark.circle",
            .deferred: "snowflake", .everything: "tray.full", .starred: "star.fill",
        ]
        for view in IssueView.builtIns {
            #expect(view.symbol == expected[view.id], Comment(rawValue: view.name))
            #expect(ViewIcon.builtIn[view.id] == expected[view.id], Comment(rawValue: view.name))
        }
        #expect(ViewIcon.builtIn.count == IssueView.builtIns.count)
    }

    @Test("built-in and user symbols are non-empty, distinct, and never a layout glyph")
    func distinct() {
        let layouts = Set(ViewLayout.allCases.map(DisplayText.layoutSymbol))
        let all = Array(ViewIcon.builtIn.values) + ViewIcon.userChoices
        #expect(all.allSatisfy { !$0.isEmpty })
        #expect(Set(all).count == all.count, "no two views share an icon by default")
        #expect(Set(all).isDisjoint(with: layouts))
    }

    @Test("the user's set is small, in order, and defaults to bookmark")
    func userChoices() {
        #expect(ViewIcon.userChoices.first == ViewIcon.defaultUserChoice)
        #expect(ViewIcon.defaultUserChoice == "bookmark")
        #expect(ViewIcon.userChoices == [
            "bookmark", "tag", "flag", "bolt", "target", "ladybug", "wrench.and.screwdriver",
            "person", "person.2", "shippingbox", "calendar", "folder", "lightbulb", "map",
        ])
    }

    @Test("the picker offers the set, with a symbol from outside it shown as the current choice")
    func pickerChoices() {
        #expect(ViewIcon.choices(including: "tag") == ViewIcon.userChoices)
        #expect(ViewIcon.choices(including: "cube") == ["cube"] + ViewIcon.userChoices)
        #expect(ViewIcon.choices(including: "") == ViewIcon.userChoices)
    }

    @Test("a view decoded with a symbol outside the set keeps it")
    func foreignSymbol() throws {
        var view = IssueView(id: "x", name: "Cubes", symbol: "cube")
        view.filter = ViewFilter()
        let decoded = try JSONDecoder().decode(IssueView.self, from: try view.documentData())
        #expect(decoded.symbol == "cube")
    }
}

@MainActor
@Suite("Icons on saved views")
struct ViewIconModelTests {
    func loadedModel() async -> WorkspaceModel {
        let model = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a", priority: 1)]), now: { t0 })
        await model.load()
        return model
    }

    @Test("Save as new view takes bookmark unless an icon was chosen")
    func saveAs() async {
        let model = await loadedModel()
        let plain = model.saveAsNewView(name: "Plain")
        #expect(plain.symbol == "bookmark")
        let flagged = model.saveAsNewView(name: "Flagged", symbol: "flag")
        #expect(flagged.symbol == "flag")
        #expect(model.sidebarViews.first { $0.id == flagged.id }?.symbol == "flag")
    }

    @Test("an icon can be changed on a user view, never on a built-in")
    func setIcon() async {
        let model = await loadedModel()
        let mine = model.saveAsNewView(name: "Mine")
        #expect(model.setIcon("map", for: mine.id))
        #expect(model.view.symbol == "map")
        #expect(!model.setIcon("map", for: .frontier))
        #expect(model.views.first { $0.id == .frontier }?.symbol == "play.circle")
        #expect(!model.setIcon("  ", for: mine.id), "an empty symbol would draw nothing")
        #expect(model.view.symbol == "map")
    }

    @Test("a duplicate keeps its source's icon until changed")
    func duplicateKeepsIcon() async {
        let model = await loadedModel()
        #expect(model.duplicateView(.frontier)?.symbol == "play.circle")
        let flagged = model.saveAsNewView(name: "Flagged", symbol: "flag")
        #expect(model.duplicateView(flagged.id)?.symbol == "flag")
    }
}
