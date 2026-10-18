import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("Command palette")
struct CommandPaletteTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("epic", title: "Print furniture", type: "epic"),
            makeIssue("epic.1", title: "Freeform furniture positioning", parent: "epic"),
            makeIssue("other", title: "Landing hero warp"),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return model
    }

    @Test("with nothing typed, every command is offered, each with a title and a unique id")
    func everything() async {
        let model = await makeModel()
        let results = CommandCatalog.results(for: "", model: model)
        #expect(results.contains(.openWorkspace))
        #expect(results.contains(.refresh))
        #expect(results.contains(.newBead))
        #expect(results.contains(.showView(.inFlight)))
        #expect(results.contains(.setLayout(.board)))
        #expect(results.allSatisfy { !$0.title.isEmpty })
        #expect(Set(results.map(\.id)).count == results.count)
    }

    @Test("commands that would do nothing aren't offered")
    func onlyWhatCanBeDone() async {
        let model = await makeModel()
        #expect(!CommandCatalog.results(for: "", model: model).contains(.editSelected), "nothing selected")
        model.selection = "epic.1"
        #expect(CommandCatalog.results(for: "", model: model).contains(.editSelected))
        #expect(!CommandCatalog.results(for: "", model: model).contains(.clearFilters), "a built-in's own rule is nothing to clear")
        model.toggleFilterValue("1", in: .priority)
        #expect(CommandCatalog.results(for: "", model: model).contains(.clearFilters))

        let readOnly = WorkspaceModel(title: "demo", store: StubStore([makeIssue("a")]), allowsWriting: false, now: { t0 })
        await readOnly.load()
        readOnly.selection = "a"
        #expect(!CommandCatalog.results(for: "", model: readOnly).contains(.newBead))
        #expect(!CommandCatalog.results(for: "", model: readOnly).contains(.editSelected))
    }

    @Test("typing picks the obvious command first")
    func ranking() async {
        let model = await makeModel()
        #expect(CommandCatalog.results(for: "refresh", model: model).first == .refresh)
        #expect(CommandCatalog.results(for: "board", model: model).first == .setLayout(.board))
        #expect(CommandCatalog.results(for: "in fl", model: model).first == .showView(.inFlight))
        // Words in any order, the way Linear's palette behaves.
        #expect(CommandCatalog.results(for: "workspace open", model: model).contains(.openWorkspace))
    }

    @Test("built-in views are found by their name and by bd's word for them")
    func views() async {
        let model = await makeModel()
        #expect(CommandCatalog.results(for: "ready", model: model).first == .showView(.frontier))
        #expect(CommandCatalog.results(for: "frontier", model: model).first == .showView(.frontier), "the name it shipped under still finds it")
        // A command whose title has the word ("Show Dependency Graph", "Order by Last closed")
        // still comes first: a title match beats an alias.
        #expect(CommandCatalog.results(for: "blocked", model: model).contains(.showView(.stuck)))
        #expect(CommandCatalog.results(for: "closed", model: model).contains(.showView(.landed)))
        #expect(!CommandCatalog.results(for: "", model: model).contains(.showView(.starred)), "nothing is starred")
        #expect(!CommandCatalog.results(for: "", model: model).contains(.unfocus), "nothing is focused")
        model.focus(on: "epic")
        #expect(CommandCatalog.results(for: "", model: model).contains(.unfocus))
    }

    @Test("Save, Save as new view and Reset are offered only while the view is modified; Save only on a user view")
    func viewSaving() async {
        let model = await makeModel()
        let quiet = CommandCatalog.results(for: "", model: model)
        #expect(!quiet.contains(.saveView) && !quiet.contains(.saveViewAs) && !quiet.contains(.resetView))

        model.toggleFilterValue("1", in: .priority)
        let modified = CommandCatalog.results(for: "", model: model)
        #expect(!modified.contains(.saveView), "a built-in's filter is its definition")
        #expect(modified.contains(.saveViewAs))
        #expect(modified.contains(.resetView))
        // "Reset Columns" and "Reset Configuration…" tie on the title and the palette breaks
        // ties on length, so it is offered rather than first.
        #expect(CommandCatalog.results(for: "reset", model: model).contains(.resetView))
        #expect(CommandCatalog.results(for: "reset view", model: model).first == .resetView)
        #expect(CommandCatalog.results(for: "save as", model: model).first == .saveViewAs)

        model.saveAsNewView(name: "Mine")
        model.layout = .board
        let user = CommandCatalog.results(for: "", model: model)
        #expect(user.contains(.saveView))
        #expect(CommandCatalog.results(for: "save", model: model).prefix(2).contains(.saveView))
        #expect(AppCommand.saveView.shortcut == "⌘S")
        #expect(AppCommand.saveViewAs.shortcut == "⌥⌘S")
        #expect(AppCommand.resetView.shortcut == "⌥⌘R")
        #expect([AppCommand.saveView, .saveViewAs, .resetView].allSatisfy { $0.group == "Views" })
    }

    @Test("commands answer to the words people actually type")
    func aliases() async {
        let model = await makeModel()
        // "fin" is what you type when you want Find; the command needn't be titled that exactly.
        #expect(CommandCatalog.results(for: "fin", model: model).first == .focusSearch)
        #expect(CommandCatalog.results(for: "find", model: model).first == .focusSearch)
        #expect(CommandCatalog.results(for: "reload", model: model).first == .refresh)
        // "column" now reaches the columns themselves, which is more direct than the menu holding them.
        if case .toggleColumn = CommandCatalog.results(for: "column", model: model).first {} else {
            Testing.Issue.record("column should offer a column first")
        }
        #expect(CommandCatalog.results(for: "display", model: model).first == .displayOptions)
// "sort" should reach the ordering commands themselves before the menu that holds them.
        if case .setOrdering = CommandCatalog.results(for: "sort", model: model).first {} else {
            Testing.Issue.record("sort should offer an ordering first")
        }
        #expect(CommandCatalog.results(for: "help", model: model).first == .showShortcuts)
        #expect(CommandCatalog.results(for: "kanban", model: model).first == .setLayout(.board))
    }

    @Test("a short query filters on what's written on screen, not on hidden aliases")
    func shortQueriesAreLiteral() async {
        let model = await makeModel()
        for command in CommandCatalog.results(for: "c", model: model) {
            #expect(command.title.lowercased().contains("c"), "\(command.title) has no c in it")
        }
        for command in CommandCatalog.results(for: "ne", model: model) {
            #expect(command.title.lowercased().contains("ne"), "\(command.title) doesn't contain \"ne\"")
        }
        // Three letters is enough to mean something, so aliases come back.
        #expect(CommandCatalog.results(for: "fin", model: model).first == .focusSearch)
        #expect(CommandCatalog.results(for: "kanban", model: model).first == .setLayout(.board))
    }

    @Test("a title match still beats an alias match")
    func titleWins() async {
        let model = await makeModel()
        #expect(CommandCatalog.results(for: "refresh", model: model).first == .refresh)
        #expect(CommandCatalog.results(for: "display", model: model).first == .displayOptions)
    }

    @Test("beads are searchable from the palette, by id or by title")
    func beads() async {
        let model = await makeModel()
        let byTitle = CommandCatalog.results(for: "freeform", model: model)
        #expect(byTitle.contains(.goToIssue("epic.1", title: "Freeform furniture positioning")))
        let byID = CommandCatalog.results(for: "epic.1", model: model)
        #expect(byID.first == .goToIssue("epic.1", title: "Freeform furniture positioning"))
        #expect(!CommandCatalog.results(for: "", model: model).contains { $0.isGoToIssue }, "not before you type")
    }

    @Test("a query that matches nothing returns nothing, rather than everything")
    func noMatches() async {
        let model = await makeModel()
        #expect(CommandCatalog.results(for: "zzzzqq", model: model).isEmpty)
    }

    @Test("commands say where they belong and which keys run them")
    func presentation() async {
        let model = await makeModel()
        #expect(AppCommand.refresh.shortcut == "⌘R")
        #expect(AppCommand.openWorkspace.shortcut == "⌘O")
        // Both keys are real, and both are shown: the plain one, and the ⌘ one that still works
        // while a text field has the keyboard.
        #expect(AppCommand.focusSearch.shortcut == "/ or ⌘F")
        #expect(AppCommand.focusSearch.bindings.first?.isPlainKey == true)
        #expect(AppCommand.refresh.bindings.allSatisfy { !$0.isPlainKey })
        #expect(AppCommand.newBead.group == "Beads")
        #expect(CommandCatalog.results(for: "", model: model).allSatisfy { !$0.group.isEmpty })
    }
}

@MainActor
@Suite("Palette matching stays honest")
struct PaletteMatchingTests {
    @Test("a query only matches commands that actually relate to it")
    func noFalsePositives() async {
        let store = MemoryStore([makeIssue("a", title: "Tile cache")])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        let results = CommandCatalog.results(for: "them", model: model)
        #expect(!results.isEmpty, "\"them\" should find the theme commands")
        for command in results {
            let text = (command.title + " " + command.keywords.joined(separator: " ")).lowercased()
            #expect(text.contains("them") || text.contains("theme"), "\(command.title) has nothing to do with \"them\"")
        }
    }
}
