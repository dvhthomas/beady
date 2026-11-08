import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// The Library tier: one `.beadyview` document per view in a folder, read at launch.
@Suite("The view Library on disk")
struct ViewLibraryFilesTests {
    func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("beady-views-\(UUID().uuidString)", isDirectory: true)
    }

    func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "beady-tests-\(UUID().uuidString)")!
    }

    func makeView(_ name: String, id: String) -> IssueView {
        IssueView(
            id: IssueView.ID(id), name: name, symbol: "bookmark",
            filter: ViewFilter(rules: [FilterRule(field: .labels, op: .includesAny, values: [name.lowercased()])]),
            presentation: ViewPresentation(layout: .board, grouping: .status, ordering: .priority)
        )
    }

    func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test("loads every .beadyview in the folder: user views in name order after the built-ins, a built-in's file contributing only its presentation")
    func loadFromDirectory() throws {
        let directory = scratchDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeView("Tiles", id: "tiles").documentData().write(to: directory.appendingPathComponent("tiles.beadyview"))
        try makeView("Agents", id: "agents").documentData().write(to: directory.appendingPathComponent("agents.beadyview"))
        var pipeline = IssueView.builtIn(.pipeline)!
        pipeline.name = "Renamed by hand"
        pipeline.presentation.layout = .list
        try pipeline.documentData().write(to: directory.appendingPathComponent("pipeline.beadyview"))
        try Data("not a view".utf8).write(to: directory.appendingPathComponent("broken.beadyview"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let library = ViewLibrary.load(from: directory, preferences: nil)
        #expect(library.views.map(\.name) == IssueView.builtIns.map(\.name) + ["Agents", "Tiles"])
        #expect(library.view(.pipeline)?.presentation.layout == .list)
        #expect(library.view(.pipeline)?.name == "Pipeline", "the table stays the definition")
        #expect(library.view(IssueView.ID("tiles"))?.filter == makeView("Tiles", id: "tiles").filter)

        // A folder that isn't there yet is simply empty.
        #expect(ViewLibrary.load(from: scratchDirectory(), preferences: nil).views == IssueView.builtIns)
    }

    @Test("save writes a file per user view and per built-in whose presentation changed, and removes the file of a deleted view")
    func saveAndDelete() {
        let directory = scratchDirectory()
        var library = ViewLibrary()
        library.views.append(makeView("Mine", id: "mine"))
        library.save(to: directory, preferences: nil)
        #expect(files(in: directory) == ["mine.beadyview"])

        let ready = library.views.firstIndex { $0.id == .frontier }!
        library.views[ready].presentation.layout = .board
        library.save(to: directory, preferences: nil)
        #expect(files(in: directory) == ["frontier.beadyview", "mine.beadyview"])
        #expect(ViewLibrary.load(from: directory, preferences: nil) == library)

        library.views[ready].presentation = IssueView.builtIn(.frontier)!.presentation
        library.save(to: directory, preferences: nil)
        #expect(files(in: directory) == ["mine.beadyview"], "a built-in back on its defaults needs no file")

        library.views.removeAll { $0.id == IssueView.ID("mine") }
        library.save(to: directory, preferences: nil)
        #expect(files(in: directory).isEmpty)
    }

    @Test("a document is the section-5 JSON: a beadyView header and plain ids, and it reads back")
    func document() throws {
        let view = makeView("Agent tiles", id: "2F1A")
        let data = try view.documentData()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["beadyView"] as? Int == 1)
        #expect(json["id"] as? String == "2F1A")
        #expect(json["name"] as? String == "Agent tiles")
        #expect(try ViewLibrary.views(fromDocument: data) == [view])
        #expect(view.exportFilename == "Agent tiles.beadyview")
        #expect(makeView("a/b: c", id: "x").exportFilename == "a-b- c.beadyview")
    }

    @Test("importing a view whose id is taken gives it a fresh id and a suffixed name; the file's built-in flag is ignored")
    func importClash() {
        var library = ViewLibrary()
        library.views.append(makeView("Mine", id: "mine"))
        var fakeBuiltIn = makeView("Frontier++", id: IssueView.ID.frontier.rawValue)
        fakeBuiltIn.isBuiltIn = true
        let imported = library.importViews([makeView("Mine", id: "mine"), fakeBuiltIn])
        #expect(imported.map(\.name) == ["Mine (imported)", "Frontier++ (imported)"])
        #expect(imported.allSatisfy { $0.id != IssueView.ID("mine") && $0.id != .frontier && !$0.isBuiltIn })
        #expect(library.views.filter { !$0.isBuiltIn }.count == 3)
        #expect(library.view(.frontier) == IssueView.builtIn(.frontier), "a built-in can't be imported over")

        let fresh = library.importViews([makeView("Other", id: "other")])
        #expect(fresh.first?.id == IssueView.ID("other"))
        #expect(fresh.first?.name == "Other")
    }

    @Test("a .beadyviews file is an array of views, imported one by one")
    func importArray() throws {
        let views = [makeView("A", id: "a"), makeView("B", id: "b")]
        let data = try ViewLibrary.documentData(for: views)
        #expect(try ViewLibrary.views(fromDocument: data) == views)
        var library = ViewLibrary()
        let imported = library.importViews(try ViewLibrary.views(fromDocument: data))
        #expect(imported.map(\.name) == ["A", "B"])
        #expect(library.views.suffix(2).map(\.name) == ["A", "B"])
    }

    @Test("a document from a newer Beady, or no view at all, is refused with a readable error")
    func unknownVersion() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: makeView("A", id: "a").documentData()) as? [String: Any])
        json["beadyView"] = 7
        let newer = try JSONSerialization.data(withJSONObject: json)
        #expect {
            try ViewLibrary.views(fromDocument: newer)
        } throws: { error in
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            return text.contains("newer") && text.contains("7")
        }
        #expect {
            try ViewLibrary.views(fromDocument: Data("{\"hello\": 1}".utf8))
        } throws: { error in
            ((error as? LocalizedError)?.errorDescription ?? "").contains("Beady view")
        }
        #expect(throws: (any Error).self) { try ViewLibrary.views(fromDocument: Data("nonsense".utf8)) }
    }

    @Test("views an older Beady kept in preferences move to files once")
    func migratesPreferences() throws {
        let directory = scratchDirectory()
        let defaults = scratchDefaults()
        var frontier = IssueView.builtIn(.frontier)!
        frontier.presentation.layout = .board
        defaults.set(try JSONEncoder().encode([frontier, makeView("Mine", id: "mine")]), forKey: "views")

        let library = ViewLibrary.load(from: directory, preferences: defaults)
        #expect(library.view(.frontier)?.presentation.layout == .board)
        #expect(library.views.last?.name == "Mine")
        #expect(files(in: directory) == ["frontier.beadyview", "mine.beadyview"])
        #expect(defaults.data(forKey: "views") == nil)
        #expect(ViewLibrary.load(from: directory, preferences: defaults) == library)
    }
}
