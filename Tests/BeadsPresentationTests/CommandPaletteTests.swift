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
        #expect(results.contains(.showView(.lifecycle(.inFlight))))
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
        #expect(!CommandCatalog.results(for: "", model: model).contains(.clearFilters), "no filters to clear")
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
        #expect(CommandCatalog.results(for: "in fl", model: model).first == .showView(.lifecycle(.inFlight)))
        // Words in any order, the way Linear's palette behaves.
        #expect(CommandCatalog.results(for: "workspace open", model: model).contains(.openWorkspace))
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
